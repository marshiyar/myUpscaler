#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x48:rate=24:duration=2' -itsoffset 0.2 -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' -itsoffset 0.4 -f lavfi -i 'sine=frequency=660:sample_rate=48000:duration=2.5' -map 0:v -map 1:a -map 2:a -vf "select='not(eq(mod(n,5),0))'" -fps_mode vfr -c:v libx264 -pix_fmt yuv420p -c:a aac "$TEST_DIR/source.mp4"
"$FFMPEG" -hide_banner -loglevel error -i "$TEST_DIR/source.mp4" -map 0:v -c copy -metadata:s:v:0 rotate=90 "$TEST_DIR/rendered.mp4"
"$FFMPEG" -hide_banner -loglevel error -i "$TEST_DIR/source.mp4" -map 0:a -c copy "$TEST_DIR/audio.m4a"
xcrun swiftc -whole-module-optimization -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -module-cache-path "$TEST_DIR/module-cache" -swift-version 5 \
  -target arm64-apple-macos15.2 -O \
  myUpscaler/Processing/VideoIO.swift myUpscaler/Processing/VideoAudioMuxer.swift \
  tests/apple-api/VideoAudioMuxRegression.swift -o "$TEST_DIR/VideoAudioMuxRegression"
"$TEST_DIR/VideoAudioMuxRegression" "$TEST_DIR"
"$FFMPEG" -hide_banner -loglevel error -i "$TEST_DIR/muxed.mp4" -f null -
