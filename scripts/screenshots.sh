#!/bin/zsh
# Opens the built app at each lesson's demo and captures the window into docs/images/.
# Usage: scripts/screenshots.sh [lesson-id ...]   (needs Screen Recording permission for your terminal)
# DEMO_PART=gamut scripts/screenshots.sh colour   opens a specific tab of a multi-part demo
set -e
cd "$(dirname "$0")/.."
APP="build/Build/Products/Release/Signal Processing Primer.app"
ids=("$@")
(( $# )) || ids=(signals sampling quantization fourier windows spectrogram convolution filters dynamics images jpeg film)
for id in $ids; do
  pkill -x "Signal Processing Primer" 2>/dev/null || true; sleep 1
  extra=(); [[ -n $DEMO_PART ]] && extra=(-demoPart "$DEMO_PART")
  open -n "$APP" --args -initialLesson "$id" -scrollToDemo YES "${extra[@]}"
  wid=""
  for _ in {1..15}; do sleep 1; wid=$(swift scripts/window_id.swift); [[ -n $wid ]] && break; done
  [[ -n $wid ]] || { echo "no window for $id"; continue; }
  sleep 2   # let charts and image filters finish
  screencapture -x -o -l"$wid" "docs/images/lesson-$id.png"
  sips -s format jpeg -s formatOptions 82 -Z 1400 "docs/images/lesson-$id.png" --out "docs/images/lesson-$id.jpg" >/dev/null
  rm "docs/images/lesson-$id.png"
  echo "captured $id"
done
pkill -x "Signal Processing Primer" 2>/dev/null || true
