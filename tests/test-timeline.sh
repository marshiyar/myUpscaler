#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if (( $# == 0 )); then
  ffmpeg_path=$(command -v ffmpeg) || { echo 'Timeline checks need local ffmpeg or two existing fixture paths.' >&2; exit 1; }
  "$ffmpeg_path" -v error -f lavfi -i testsrc2=size=640x360:rate=30 -t 2 -c:v libx264 -threads 1 -g 60 -bf 2 -pix_fmt yuv420p "$work/first.mp4"
  "$ffmpeg_path" -v error -f lavfi -i testsrc2=size=320x180:rate=30 -t 2 -c:v libx264 -threads 1 -g 60 -bf 2 -pix_fmt yuv420p "$work/replacement.mp4"
  set -- "$work/first.mp4" "$work/replacement.mp4"
elif (( $# < 2 )); then
  echo 'Usage: tests/test-timeline.sh [first-video replacement-video more-videos...]' >&2
  exit 2
fi
flags=(-parse-as-library -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -module-cache-path "$work/cache")
xcrun swiftc -O "${flags[@]}" myUpscaler/State/EditorState+TimelineLoader.swift tests/timeline/TimelineTests.swift -o "$work/timeline"
for fixture in "$@"; do "$work/timeline" "$fixture"; done
xcrun swiftc "${flags[@]}" myUpscaler/State/EditorState*.swift myUpscaler/State/UpscaleSettings.swift myUpscaler/State/Settings*.swift myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,VideoInput}.swift tests/timeline/EditorTimelineTests.swift -o "$work/editor"
"$work/editor" "$1" "$2"
