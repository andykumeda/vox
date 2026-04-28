#!/bin/bash
# Usage: ./mix.sh <clean.wav> <noise.wav> <out.wav> <noise-gain>
# Mixes noise.wav (scaled by noise-gain, e.g. 0.3 ≈ -10dB) into clean.wav.
# Output matches Vox audio format: 16kHz mono Int16 PCM WAV, duration = clean.
set -e
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <clean.wav> <noise.wav> <out.wav> <noise-gain>" >&2
    exit 1
fi
ffmpeg -y -i "$1" -i "$2" -filter_complex \
    "[1:a]volume=$4[bg];[0:a][bg]amix=inputs=2:duration=first" \
    -ac 1 -ar 16000 -sample_fmt s16 "$3"
