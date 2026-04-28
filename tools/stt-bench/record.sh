#!/bin/bash
# Usage: ./record.sh <sample-name>
# Records from default macOS mic in 16kHz mono Int16 PCM WAV (matches Vox's AudioRecorder).
# Ctrl+C to stop and finalize the file.
set -e
if [ -z "$1" ]; then
    echo "Usage: $0 <sample-name>" >&2
    exit 1
fi
mkdir -p samples
ffmpeg -f avfoundation -i ":0" -ac 1 -ar 16000 -sample_fmt s16 "samples/$1.wav"
