#!/bin/bash
# Launches a built myUpscaler.app on the Upscale page with a video loaded, in light appearance, waits for the window
# to draw and saves a picture of that window (title bar included) as a PNG. Needs a signed-in macOS desktop session.
# Usage: scripts/screenshot-app.sh <app bundle> <video> <output.png> [width x height of the content, default 1280x800]
set -euo pipefail

app=${1:?app bundle}
video=${2:?video file}
output=${3:?output png}
size=${4:-1280x800}
name=$(basename "$app" .app)
work=$(mktemp -d)
cleanup() { killall "$name" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

system_profiler SPDisplaysDataType | grep -i 'resolution' || true

# The number of the app's main window, from the window server (needs no permission).
cat > "$work/window-id.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let owner = CommandLine.arguments[1].lowercased()
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String)?.lowercased() == owner
    && (window[kCGWindowLayer as String] as? Int) == 0 {
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    if (bounds["Width"] ?? 0) >= 600, let number = window[kCGWindowNumber as String] as? Int {
        print(number)
        break
    }
}
SWIFT
xcrun swiftc -O "$work/window-id.swift" -o "$work/window-id"

open -n "$app" --args --open "$video" --page upscale --appearance light --window-size "$size"

id=''
for _ in $(seq 1 60); do
  id=$("$work/window-id" "$name" || true)
  [[ -n $id ]] && break
  sleep 1
done
if [[ -z $id ]]; then
  echo "The $name window did not appear." >&2
  exit 1
fi
# The preview frame and the timeline load after the window opens.
sleep 10
id=$("$work/window-id" "$name")
mkdir -p "$(dirname "$output")"
screencapture -x -o -l "$id" "$output"
test -s "$output"
file "$output"
