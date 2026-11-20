#!/bin/bash
# Smoke test of a release build on the platform it was built for: generates a test clip, renders the real window
# headless three times (the import view, the adjustments panel on the clip, and the clip exported end to end) and
# checks that the export was written. Writes the screenshots and a one-line result to the output folder; the release
# workflow puts them on the release.
#
#   bash scripts/smoke-test.sh <app> <output folder> <platform name>     (run from desktop/)
set -euo pipefail

app=$1
out=$2
name=$3
# The scratch folder sits beside the output folder: a path the platform's own programs read as is (on Windows, a
# Git Bash temporary path is not always translated for them).
work="$out.work"
mkdir -p "$out" "$work"
trap 'rm -rf "$work"' EXIT

cargo run --quiet --release --example sample_clip -- "$work/clip.mp4"
"$app" --screenshot "$out/smoke-$name-1-import.png" --light
"$app" --screenshot "$out/smoke-$name-2-adjustments.png" --light --page 1 "$work/clip.mp4"
"$app" --screenshot "$out/smoke-$name-3-export.png" --dark --run --log "$work/clip.mp4"
test -s "$work/clip_[restored].mp4"
for shot in import adjustments export; do
  test -s "$out/smoke-$name-"*"-$shot.png"
done

size=$(wc -c < "$work/clip_[restored].mp4")
echo "passed on $(uname -sm); a 3 s test clip exported to $((size / 1024)) KB" > "$out/smoke-$name.txt"
cat "$out/smoke-$name.txt"
