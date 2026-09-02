#!/usr/bin/env bash
# Extracts frame strips from an iOS screen recording so a transition can be
# read frame by frame. Used to produce the measurements in docs/design.md.
#
#   tool/reference_frames.sh <recording> <start-seconds> [duration-seconds] [fps]
#
# Writes <recording-basename>_<start>s.png next to the recording: a grid of
# frames, eight per row, sampled at <fps> (default 30) for <duration>
# (default 1.3 s) from <start>. Requires ffmpeg.
set -euo pipefail

if [ $# -lt 2 ]; then
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
fi

input=$1
start=$2
duration=${3:-1.3}
fps=${4:-30}
output="${input%.*}_${start}s.png"

ffmpeg -v error -y -ss "$start" -t "$duration" -i "$input" \
  -vf "fps=${fps},scale=200:-1,tile=8x5:margin=2:padding=2" "$output"

echo "$output"
