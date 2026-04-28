#!/bin/bash
# Usage: ./record.sh <sample-name>
# Records from a macOS mic in 16kHz mono Int16 PCM WAV (matches Vox's AudioRecorder).
# Ctrl+C to stop and finalize the file.
#
# Device selection: defaults to avfoundation index 1 (typical real mic). Override with:
#   AVFOUNDATION_DEVICE=":2" ./record.sh foo
# List devices: ffmpeg -f avfoundation -list_devices true -i ""
set -e
if [ -z "$1" ]; then
    echo "Usage: $0 <sample-name>" >&2
    exit 1
fi
DEV="${AVFOUNDATION_DEVICE:-:1}"
mkdir -p samples
ffmpeg -f avfoundation -i "$DEV" -ac 1 -ar 16000 -sample_fmt s16 "samples/$1.wav"
