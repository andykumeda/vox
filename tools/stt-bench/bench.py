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


def main() -> int:
    load_dotenv(ROOT / ".env")
    print("bench.py skeleton ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
