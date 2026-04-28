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

freesound.org CC0 clips, normalized to 16kHz mono Int16 WAV via the
`mkdir -p noise` + ffmpeg loop in the plan (Task 10 step 2).

- Cafe ambient: freesound 380202 (lunchmoney, "cafe ambience day 1")
- Podcast/voice: freesound 487881 (donalddrum10, "anecdote podcast")
- Typing: freesound 567920 (luutoo, "keyboard typing 1 sentence")

## Bench run history

### 2026-04-28 — first run

**Verdict:** no clear accuracy winner over current OpenAI; pain B
(real-speech mishears) is upstream of provider choice. Deepgram is a
viable tradeoff candidate (cheaper + faster + correct empty-transcript
on silence) at small accuracy cost.

**Per-pain breakdown:**
- *Pain A (hallucinations on silence)*: OpenAI hallucinated
  `"The sun is shining brightly."` on the silent probe. Deepgram and
  AssemblyAI correctly returned empty.
- *Pain B (mishears, real prose)*: all three providers shared
  Whisper-family weaknesses on names (sample 07: "Reza"→"Riza",
  "Saoirse"→"Sayori" across the board; AssemblyAI also hallucinated
  "Lupin" and turned "metrics" into "matrix"). OpenAI most accurate on
  clean prose; AssemblyAI worst (semantic flip on sample 08:
  "the legal" → "illegal").

**Cost / latency totals (13 samples):**

| Provider   | Total cost | Avg latency |
|------------|-----------:|------------:|
| openai     |  $0.01672  |    1.45s    |
| deepgram   |  $0.01198  |    0.54s    |
| assemblyai |  $0.01728  |    1.98s    |

**Recommended next steps:**
1. Investigate pain B upstream of the provider — wire Vox's
   DictionaryStore into the prompt as hot-words / vocabulary; tune mic
   gain; add VAD pre-gating.
2. If pain A is the priority, brainstorm Deepgram integration into Vox
   as a separate spec.
3. WER pass not warranted — qualitative gaps were clear.

Full per-sample transcripts: `outputs/2026-04-28-202114/results.md`
(gitignored).
