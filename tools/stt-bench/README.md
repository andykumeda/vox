# stt-bench

Throwaway CLI to compare batch STT providers (OpenAI, Deepgram, AssemblyAI) on a fixed set of prose-mode WAV samples.

Spec: `../../docs/superpowers/specs/2026-04-28-stt-bench-design.md`

## Setup

1. `python3 -m venv .venv && source .venv/bin/activate`
2. `pip install -r requirements.txt`
3. `cp .env.example .env`, fill in API keys.
4. `brew install ffmpeg` (if missing).

## Capture samples

`./record.sh 01-prose-short` — Ctrl+C to stop. Repeat for samples 01–10 per `samples.txt`.

## Mix noise

Download CC0 noise WAVs (URLs below) into `noise/`, then:

```bash
./mix.sh samples/03-prose-medium.wav noise/cafe.wav samples/11-noise-cafe.wav 0.3
./mix.sh samples/03-prose-medium.wav noise/podcast.wav samples/12-noise-voice.wav 0.5
./mix.sh samples/03-prose-medium.wav noise/typing.wav samples/13-noise-typing.wav 0.4
```

## Run bench

```bash
python bench.py
```

Output: `outputs/<UTC-timestamp>/results.md` plus raw per-(sample, provider) text files.

## Pricing reference

(Confirm at run time on each provider's pricing page.)

| Provider                     | USD/min |
|------------------------------|---------|
| OpenAI gpt-4o-transcribe     | 0.006   |
| Deepgram Nova-3              | 0.0043  |
| AssemblyAI Universal         | 0.0062  |

## Noise sources

(Fill in once downloaded.)

- Cafe ambient: <freesound URL>
- Podcast/voice: <freesound URL>
- Typing: <freesound URL>
