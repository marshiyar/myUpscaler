#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
# Video at 24 fps without every fifth frame (VFR), two AAC tracks starting at 0.2 s and 0.4 s, a rotated
# video-only copy and an audio-only file, written with AVFoundation.
bash tests/fixtures/build.sh "$TEST_DIR/make-test-media"
"$TEST_DIR/make-test-media" audio-mux-set "$TEST_DIR"
xcrun swiftc -whole-module-optimization -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -module-cache-path "$TEST_DIR/module-cache" -swift-version 5 \
  -target arm64-apple-macos15.2 -O \
  myUpscaler/Processing/VideoIO.swift myUpscaler/Processing/VideoAudioMuxer.swift \
  tests/apple-api/VideoAudioMuxRegression.swift -o "$TEST_DIR/VideoAudioMuxRegression"
"$TEST_DIR/VideoAudioMuxRegression" "$TEST_DIR"
"$TEST_DIR/make-test-media" verify "$TEST_DIR/muxed.mp4"
