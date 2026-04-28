# STT Provider Benchmark Tool — Design

**Date:** 2026-04-28
**Status:** Design approved, ready for implementation plan
**Owner:** Andy

## Problem

Vox currently transcribes via OpenAI's `gpt-4o-mini-transcribe` (and tested `gpt-4o-transcribe`). Real-use accuracy is poor in prose mode, primarily:

- **Mishears** of real speech — wrong words on names, jargon, normal sentences (primary pain)
- **Hallucinations** — invented words on near-silent or short clips (secondary pain)

Both Whisper-family models exhibit these. Goal: identify a provider with materially better accuracy on Andy's voice/mic/use-case at comparable or lower cost. Provider candidates: **Deepgram Nova-3**, **AssemblyAI Universal-2**, with current OpenAI as baseline.

## Goal

Produce a side-by-side, reproducible accuracy comparison across the three providers using a representative set of Andy's real prose-mode utterances, including noisy environments. Result: a clear winner (or a clear "close call" that justifies a WER follow-up).

**Non-goals:**

- Streaming transcription (Vox is batch-only today; streaming is a separate UX-level redesign).
- Production-quality benchmark infrastructure (this is a one-shot decision aid).
- Vox integration (separate spec after winner is picked).
- Command-mode evaluation (prose is the dominant use case; command-mode failures are tracked separately).

## Approach

Standalone Python CLI in a separate repo (`~/Dev/stt-bench/`). Records WAV samples via `ffmpeg`, sends each sample through all three providers' batch HTTP APIs, writes a markdown report comparing transcripts, latency, and estimated cost. Eyeball-judged.

**Why standalone Python:** throwaway tool, ~150 LOC, all three providers have plain-HTTP batch APIs, fast iteration. Doesn't pollute Vox's Swift package or repo history. When a winner is picked, the integration into Vox will be re-implemented properly in Swift.

**Why batch-only for v1:** decision is *which provider*, not *which transport*. Batch comparison answers it cheaply and apples-to-apples. Streaming is a Vox UX change with its own scope.

## Architecture

```
stt-bench/                 # separate git repo, lives at ~/Dev/stt-bench/
├── bench.py               # main CLI (~150 lines)
├── record.sh              # ffmpeg wrapper for capturing samples
├── mix.sh                 # ffmpeg wrapper for mixing clean + noise WAVs
├── samples/               # gitignored — captured/mixed WAVs
│   ├── 01-prose-short.wav
│   ├── ...
│   └── 13-noise-typing.wav
├── samples.txt            # human notes describing each sample's purpose
├── noise/                 # gitignored — downloaded CC0 noise clips
├── outputs/               # gitignored — per-run results
│   └── 2026-04-28-103000/
│       ├── results.md
│       └── raw/<sample>-<provider>.txt
├── .env.example           # API key var names
├── .env                   # gitignored — actual keys
├── requirements.txt       # httpx (or requests)
├── .gitignore
└── README.md              # usage, noise-source URLs, provider pricing notes
```

## Components

### 1. Recorder helper (`record.sh`)

One-line wrapper:

```bash
#!/bin/bash
# Usage: ./record.sh 03-prose-medium
# Records from default macOS mic; Ctrl+C to stop.
ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 -sample_fmt s16 "samples/$1.wav"
```

Format (16 kHz / mono / Int16 PCM WAV) matches Vox's `AudioRecorder` exactly so the bench reflects what Vox would actually send.

### 2. Mixer helper (`mix.sh`)

```bash
#!/bin/bash
# Usage: ./mix.sh clean.wav noise.wav out.wav 0.3
# Mixes noise at given linear gain (e.g. 0.3 ≈ -10dB) into clean speech.
ffmpeg -i "$1" -i "$2" -filter_complex \
  "[1:a]volume=$4[bg];[0:a][bg]amix=inputs=2:duration=first" \
  -ac 1 -ar 16000 -sample_fmt s16 "$3"
```

### 3. Provider clients (inline in `bench.py`)

Three async functions, plain `httpx` calls, no SDKs:

- `transcribe_openai(wav_bytes) -> (text, latency_s)` — POST `multipart/form-data` to `https://api.openai.com/v1/audio/transcriptions`, model `gpt-4o-transcribe`, `response_format=text`, `language=en`, `temperature=0`, `prompt=` (copied verbatim from `TranscriptionMode.swift` prose case).
- `transcribe_deepgram(wav_bytes) -> (text, latency_s)` — POST raw WAV body to `https://api.deepgram.com/v1/listen?model=nova-3&punctuate=true&smart_format=true&language=en`, `Authorization: Token $KEY`. Parse `results.channels[0].alternatives[0].transcript`.
- `transcribe_assemblyai(wav_bytes) -> (text, latency_s)` — upload WAV to `/v2/upload`, POST `/v2/transcript` with `speech_model=universal`, `language_code=en`, poll `/v2/transcript/<id>` every 1s until `status` is `completed` or `error` (max 30s).

API keys via env (`OPENAI_API_KEY`, `DEEPGRAM_API_KEY`, `ASSEMBLYAI_API_KEY`); `.env.example` documents them; script loads `.env` via `python-dotenv` if present.

### 4. Runner (`bench.py main`)

1. Glob `samples/*.wav`, sort by name.
2. For each sample: read bytes, compute audio duration via WAV header.
3. For each (sample, provider): wall-clock time → call client → capture text or error.
4. Write `outputs/<UTC-timestamp>/results.md` plus raw per-(sample, provider) text files.

## Data flow

```
record.sh <name>
  ↓
samples/<name>.wav    (16kHz mono Int16 WAV, matches Vox)
  ↓ (optional: mix.sh adds noise → samples/11..13-noise-*.wav)
  ↓
bench.py
  ↓
for each WAV × {OpenAI, Deepgram, AssemblyAI}:
   text, latency_s, cost_usd
  ↓
outputs/<ts>/results.md
```

### `results.md` per-sample format

```markdown
## 03-prose-medium.wav  (15.2s audio)

| Provider   | Latency | Cost      | Transcript |
|------------|---------|-----------|------------|
| OpenAI     | 1.8s    | $0.00152  | ...        |
| Deepgram   | 0.7s    | $0.00109  | ...        |
| AssemblyAI | 2.1s    | $0.00157  | ...        |
```

Footer: total cost per provider across all samples; total latency average per provider.

### Pricing constants (hardcoded, cite source in README)

| Provider   | Rate (USD/min) |
|------------|----------------|
| OpenAI gpt-4o-transcribe   | 0.006   |
| Deepgram Nova-3            | 0.0043  |
| AssemblyAI Universal       | 0.0062  |

(Confirm rates from each provider's pricing page at implementation time; bake into README.)

## Sample set (13 prose clips)

All recorded by Andy in prose mode, using the same Whisper prose prompt across all providers (so OpenAI gets the prompt it expects; Deepgram/AssemblyAI ignore it harmlessly).

| #  | Length | Content focus |
|----|--------|---------------|
| 01 | ~5s   | Short casual sentence |
| 02 | ~5s   | Short technical sentence (one product/tool name) |
| 03 | ~15s  | Conversational paragraph (daily-update style) — **also reused as the clean source for samples 11–13** |
| 04 | ~15s  | Email/Slack tone — instructions to coworker |
| 05 | ~30s  | Long story-style — multiple sentences, no jargon |
| 06 | ~30s  | Long structured — embeds dates, numbers, names mid-sentence |
| 07 | ~15s  | Names-heavy prose — coworker/product/place names known to mishear |
| 08 | ~15s  | Disfluent — "um", restarts, mid-sentence corrections |
| 09 | ~15s  | Quiet/distant — same content as 03, spoken softer |
| 10 | ~3s   | Near-silent / very short clip — hallucination probe |
| 11 | ~15s  | Sample 03 + cafe ambient @ ~-10dB SNR (`mix.sh` w/ `0.3` gain) |
| 12 | ~15s  | Sample 03 + intelligible second speaker @ ~-6dB SNR (`0.5` gain) |
| 13 | ~15s  | Sample 03 + keyboard/typing noise @ ~-8dB SNR (`0.4` gain) |

`samples.txt` lists each sample's intended weakness. Examples 11–13 vary only in the noise track, isolating noise impact across providers.

Noise sources: 3 CC0 clips from freesound.org (cafe / podcast-snippet / typing); URLs documented in `README.md`. Downloaded once into `noise/`, mixed via `mix.sh`.

## Error handling

- **Missing API key:** print `Skipping <provider>: <ENV_VAR> not set`, continue.
- **HTTP error / timeout (60s per call):** print `<provider> failed on <sample>: <status> <body[:200]>`, write `ERROR: ...` into transcript cell, continue.
- **AssemblyAI polling:** max 30s, then write `TIMEOUT`.
- **Empty / silent WAV:** pass through (sample 10 depends on this).
- **No retries.** Skews latency comparison and adds complexity.

## Testing

No unit tests for the bench tool itself — throwaway, ~150 LOC, output is human-judged.

Smoke check before the real run:
1. Place one ~3s WAV in `samples/`, run `bench.py`, confirm all three providers return non-empty text and `results.md` renders.
2. Temporarily unset one API key, re-run, confirm graceful skip and remaining providers still work.

That's it.

## Lifecycle

1. **Build the bench tool** — `bench.py`, `record.sh`, `mix.sh`, `.env.example`, `README.md`.
2. **Record 10 clean samples** + download noise + mix 3 noisy samples.
3. **Run smoke check.** Then run full bench.
4. **Eyeball `results.md`.**
   - If a provider clearly wins: declare winner, archive `stt-bench` repo.
   - If close call: add a WER pass — type ground-truth for each sample into `samples.txt`, extend `bench.py` to compute WER per provider via `jiwer`, re-render `results.md` with a WER column.
5. **New brainstorm/spec for Vox integration** of the winning provider. Not part of this work.

## Decisions made during brainstorming

- **Standalone Python, not Swift.** Bench tool is throwaway; Python iteration speed beats Swift code reuse for ~150 LOC of HTTP-and-print.
- **Batch only, no streaming in v1.** Streaming is a Vox UX change. Decide provider first.
- **Three providers (OpenAI, Deepgram, AssemblyAI).** Three is enough signal; more is noise. Whisper-family alternatives (Groq, etc.) skipped — same family, same expected mishear/hallucination profile.
- **Eyeball before WER.** WER infra only matters if eyeball is inconclusive.
- **Mix noise, don't record-with-speakers.** Mixing gives identical audio to all providers; live re-recording confounds the noise variable with mic-capture variation.
- **Repo lives outside Vox.** Keeps Vox repo and Swift package clean.

## Out of scope

- Streaming / partial transcripts.
- Vox integration of any provider.
- Command-mode evaluation.
- Multi-language evaluation.
- Diarization / speaker labels.
- Continuous regression suite (this is one-shot).
