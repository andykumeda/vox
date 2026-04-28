#!/usr/bin/env python3
"""STT provider benchmark — see README.md for usage."""
from __future__ import annotations

import asyncio
import os
import struct
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import httpx
from dotenv import load_dotenv

ROOT = Path(__file__).parent
SAMPLES_DIR = ROOT / "samples"
OUTPUTS_DIR = ROOT / "outputs"

# Pricing in USD per minute. Confirm against provider pricing pages.
PRICING_USD_PER_MIN = {
    "openai": 0.006,     # gpt-4o-transcribe
    "deepgram": 0.0043,  # Nova-3
    "assemblyai": 0.0062, # Universal
}

# Whisper prose prompt — copied verbatim from Vox's TranscriptionMode.swift `.prose` case.
# OpenAI uses it; Deepgram/AssemblyAI ignore it harmlessly (no prompt parameter sent to them).
PROSE_PROMPT = (
    "Standard English prose with natural punctuation. Break independent clauses "
    "into separate sentences with periods. Avoid long comma-chained sentences; do "
    "not stitch multiple complete thoughts together with commas. Reserve commas "
    "for short parenthetical phrases, list items, or before a single coordinator "
    "inside one clause. Use digits for dates, years, phone numbers, addresses, "
    "prices, times, measurements, and quantities of ten or more; spell out small "
    "whole numbers in ordinary prose. Preserve URLs, domains, and file names "
    "exactly (e.g., youtube.com, github.com/user/repo, README.md) without "
    "inserting spaces around the dot."
)


def wav_duration_seconds(path: Path) -> float:
    """Read a 16-bit PCM WAV header and compute duration in seconds.

    Assumes the format Vox + record.sh produce (16kHz mono Int16 PCM).
    """
    with path.open("rb") as f:
        header = f.read(44)
    if header[:4] != b"RIFF" or header[8:12] != b"WAVE":
        raise ValueError(f"{path}: not a RIFF/WAVE file")
    sample_rate = struct.unpack("<I", header[24:28])[0]
    bits_per_sample = struct.unpack("<H", header[34:36])[0]
    channels = struct.unpack("<H", header[22:24])[0]
    file_size = path.stat().st_size
    data_bytes = file_size - 44
    bytes_per_sample = (bits_per_sample // 8) * channels
    if bytes_per_sample == 0 or sample_rate == 0:
        raise ValueError(f"{path}: invalid WAV header")
    return data_bytes / bytes_per_sample / sample_rate


async def transcribe_openai(client: httpx.AsyncClient, wav_bytes: bytes) -> tuple[str, float]:
    """Returns (transcript, latency_seconds). Raises on HTTP error."""
    api_key = os.environ["OPENAI_API_KEY"]
    files = {
        "file": ("audio.wav", wav_bytes, "audio/wav"),
    }
    data = {
        "model": "gpt-4o-transcribe",
        "response_format": "text",
        "language": "en",
        "temperature": "0",
        "prompt": PROSE_PROMPT,
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    started = time.monotonic()
    resp = await client.post(
        "https://api.openai.com/v1/audio/transcriptions",
        headers=headers,
        files=files,
        data=data,
        timeout=60.0,
    )
    latency = time.monotonic() - started
    resp.raise_for_status()
    return resp.text.strip(), latency


async def transcribe_deepgram(client: httpx.AsyncClient, wav_bytes: bytes) -> tuple[str, float]:
    """Returns (transcript, latency_seconds). Raises on HTTP error."""
    api_key = os.environ["DEEPGRAM_API_KEY"]
    headers = {
        "Authorization": f"Token {api_key}",
        "Content-Type": "audio/wav",
    }
    params = {
        "model": "nova-3",
        "language": "en",
        "punctuate": "true",
        "smart_format": "true",
    }
    started = time.monotonic()
    resp = await client.post(
        "https://api.deepgram.com/v1/listen",
        headers=headers,
        params=params,
        content=wav_bytes,
        timeout=60.0,
    )
    latency = time.monotonic() - started
    resp.raise_for_status()
    payload = resp.json()
    transcript = (
        payload.get("results", {})
        .get("channels", [{}])[0]
        .get("alternatives", [{}])[0]
        .get("transcript", "")
    )
    return transcript.strip(), latency


async def transcribe_assemblyai(client: httpx.AsyncClient, wav_bytes: bytes) -> tuple[str, float]:
    """Returns (transcript, latency_seconds).

    AssemblyAI is upload + create transcript + poll. The returned latency is
    wall-clock from upload start through to terminal poll status, so it includes
    upload, create, and polling round-trips (this is the user-facing latency
    a real client would see). The 30s polling cap is measured separately, from
    after the create response, and does not include upload time.
    """
    api_key = os.environ["ASSEMBLYAI_API_KEY"]
    headers = {"Authorization": api_key}
    started = time.monotonic()

    upload_resp = await client.post(
        "https://api.assemblyai.com/v2/upload",
        headers=headers,
        content=wav_bytes,
        timeout=60.0,
    )
    upload_resp.raise_for_status()
    upload_url = upload_resp.json()["upload_url"]

    create_resp = await client.post(
        "https://api.assemblyai.com/v2/transcript",
        headers={**headers, "Content-Type": "application/json"},
        json={
            "audio_url": upload_url,
            "speech_model": "universal",
            "language_code": "en",
            "punctuate": True,
            "format_text": True,
        },
        timeout=60.0,
    )
    create_resp.raise_for_status()
    transcript_id = create_resp.json()["id"]

    poll_started = time.monotonic()
    while True:
        if time.monotonic() - poll_started > 30.0:
            raise TimeoutError(f"AssemblyAI transcript {transcript_id} did not complete in 30s")
        poll_resp = await client.get(
            f"https://api.assemblyai.com/v2/transcript/{transcript_id}",
            headers=headers,
            timeout=30.0,
        )
        poll_resp.raise_for_status()
        body = poll_resp.json()
        status = body["status"]
        if status == "completed":
            text = (body.get("text") or "").strip()
            return text, time.monotonic() - started
        if status == "error":
            raise RuntimeError(f"AssemblyAI error: {body.get('error')}")
        await asyncio.sleep(1.0)


PROVIDERS: list[tuple[str, str, callable]] = [
    ("openai", "OPENAI_API_KEY", transcribe_openai),
    ("deepgram", "DEEPGRAM_API_KEY", transcribe_deepgram),
    ("assemblyai", "ASSEMBLYAI_API_KEY", transcribe_assemblyai),
]


def estimate_cost_usd(provider: str, duration_s: float) -> float:
    rate = PRICING_USD_PER_MIN[provider]
    return rate * (duration_s / 60.0)


async def run_provider(
    provider: str,
    fn: callable,
    client: httpx.AsyncClient,
    wav_bytes: bytes,
) -> tuple[str, float]:
    """Returns (transcript_or_error_marker, latency_seconds)."""
    try:
        return await fn(client, wav_bytes)
    except httpx.HTTPStatusError as e:
        body = (e.response.text or "")[:200]
        msg = f"ERROR: HTTP {e.response.status_code} {body}"
        print(f"{provider} failed: {msg}", file=sys.stderr)
        return msg, 0.0
    except (httpx.TimeoutException, asyncio.TimeoutError) as e:
        msg = f"ERROR: timeout ({type(e).__name__})"
        print(f"{provider} failed: {msg}", file=sys.stderr)
        return msg, 0.0
    except Exception as e:
        msg = f"ERROR: {type(e).__name__}: {e}"
        print(f"{provider} failed: {msg}", file=sys.stderr)
        return msg, 0.0


def md_escape_cell(text: str) -> str:
    """Escape a transcript for use inside a markdown table cell."""
    return text.replace("|", "\\|").replace("\n", " ").replace("\r", " ")


async def run_bench() -> int:
    load_dotenv(ROOT / ".env")

    samples = sorted(SAMPLES_DIR.glob("*.wav"))
    if not samples:
        print(f"No WAVs in {SAMPLES_DIR}", file=sys.stderr)
        return 1

    active = [(name, fn) for name, env, fn in PROVIDERS if os.environ.get(env)]
    skipped = [name for name, env, _ in PROVIDERS if not os.environ.get(env)]
    for name in skipped:
        env = next(e for n, e, _ in PROVIDERS if n == name)
        print(f"Skipping {name}: {env} not set", file=sys.stderr)
    if not active:
        print("No providers configured", file=sys.stderr)
        return 1

    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d-%H%M%S")
    out_dir = OUTPUTS_DIR / ts
    raw_dir = out_dir / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    results: dict[Path, dict[str, tuple[str, float]]] = {}
    durations: dict[Path, float] = {}

    async with httpx.AsyncClient() as client:
        for sample in samples:
            wav_bytes = sample.read_bytes()
            duration = wav_duration_seconds(sample)
            durations[sample] = duration
            print(f"[{sample.name}] {duration:.1f}s", file=sys.stderr)

            tasks = [run_provider(name, fn, client, wav_bytes) for name, fn in active]
            outcomes = await asyncio.gather(*tasks)
            results[sample] = {name: outcome for (name, _), outcome in zip(active, outcomes)}

            for name, (text, _) in results[sample].items():
                (raw_dir / f"{sample.stem}-{name}.txt").write_text(text + "\n")

    lines: list[str] = []
    lines.append(f"# stt-bench results — {ts}\n")
    lines.append(f"Active providers: {', '.join(name for name, _ in active)}\n")
    if skipped:
        lines.append(f"Skipped: {', '.join(skipped)}\n")
    lines.append("")

    totals_cost: dict[str, float] = {name: 0.0 for name, _ in active}
    totals_latency: dict[str, list[float]] = {name: [] for name, _ in active}

    for sample in samples:
        duration = durations[sample]
        lines.append(f"## {sample.name}  ({duration:.1f}s audio)\n")
        lines.append("| Provider   | Latency  | Cost      | Transcript |")
        lines.append("|------------|----------|-----------|------------|")
        for name, _ in active:
            text, latency = results[sample][name]
            cost = estimate_cost_usd(name, duration)
            totals_cost[name] += cost
            totals_latency[name].append(latency)
            lines.append(
                f"| {name:<10} | {latency:>5.2f}s  | ${cost:>7.5f} | {md_escape_cell(text)} |"
            )
        lines.append("")

    lines.append("## Totals\n")
    lines.append("| Provider   | Total cost | Avg latency |")
    lines.append("|------------|------------|-------------|")
    for name, _ in active:
        avg = (sum(totals_latency[name]) / len(totals_latency[name])) if totals_latency[name] else 0.0
        lines.append(f"| {name:<10} | ${totals_cost[name]:>8.5f} | {avg:>6.2f}s     |")

    (out_dir / "results.md").write_text("\n".join(lines) + "\n")
    print(f"\nWrote {out_dir / 'results.md'}", file=sys.stderr)
    return 0


def main() -> int:
    return asyncio.run(run_bench())


if __name__ == "__main__":
    sys.exit(main())
