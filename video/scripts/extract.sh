#!/usr/bin/env bash
# Extracts frames, audio, and a spectrogram from a source video for manual
# inspection. Derived outputs land under frames/<stem>/ and audio/<stem>.wav
# (both gitignored - regenerate any time from videos/).
#
# Usage: scripts/extract.sh videos/some-clip.mp4 [fps]

set -euo pipefail

video="${1:?usage: extract.sh videos/some-clip.mp4 [fps]}"
fps="${2:-1}"
stem="$(basename "${video%.*}")"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
frames_dir="$root/frames/$stem"
audio_dir="$root/audio"

mkdir -p "$frames_dir" "$audio_dir"

ffmpeg -y -v error -i "$video" -vf "fps=$fps" "$frames_dir/frame_%03d.jpg"
ffmpeg -y -v error -i "$video" -vn -ac 1 -ar 48000 -acodec pcm_s16le "$audio_dir/$stem.wav"
ffmpeg -y -v error -i "$video" -filter_complex "showspectrumpic=s=1024x512:legend=1" "$frames_dir/../$stem-spectrogram.png"

echo "frames:       $frames_dir/"
echo "audio:        $audio_dir/$stem.wav"
echo "spectrogram:  $root/frames/$stem-spectrogram.png"
