#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
FFMPEG="${FFMPEG:-/opt/homebrew/bin/ffmpeg}"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x48:rate=24000/1001' -f lavfi -i 'sine=frequency=440:sample_rate=48000:duration=3' -frames:v 48 -c:v libx264 -bf 3 -pix_fmt yuv420p -c:a aac "$TEST_DIR/fractional.mp4"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x48:rate=30:duration=2' -c:v libx264 -bf 3 -pix_fmt yuv420p "$TEST_DIR/integer.mp4"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x48:rate=24:duration=2' -vf "select='not(eq(mod(n,5),0))'" -fps_mode vfr -c:v libx264 "$TEST_DIR/variable.mp4"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'sine=duration=1' -c:a aac "$TEST_DIR/audio.m4a"
"$FFMPEG" -hide_banner -loglevel error -f lavfi -i 'testsrc2=size=64x48:rate=30' -frames:v 1 -c:v libx264 "$TEST_DIR/single.mp4"
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -swift-version 5 \
  -target arm64-apple-macos15.2 myUpscaler/Processing/SourceVideoTiming.swift \
  tests/apple-api/SourceVideoTimingRegression.swift -o "$TEST_DIR/SourceVideoTimingRegression"
"$TEST_DIR/SourceVideoTimingRegression" "$TEST_DIR"
