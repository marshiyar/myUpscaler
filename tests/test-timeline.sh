#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if (( $# == 0 )); then
  # Two seconds at 30 fps with B-frames, written with AVFoundation.
  bash tests/fixtures/build.sh "$work/make-test-media"
  "$work/make-test-media" clip "$work/first.mp4" 640 360 30 1 60
  "$work/make-test-media" clip "$work/replacement.mp4" 320 180 30 1 60
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
