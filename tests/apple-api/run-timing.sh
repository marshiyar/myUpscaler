#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
# 24000/1001 and 30 fps with B-frames, variable rate, audio-only and single-frame files, written with AVFoundation.
bash tests/fixtures/build.sh "$TEST_DIR/make-test-media"
"$TEST_DIR/make-test-media" timing-set "$TEST_DIR"
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -swift-version 5 \
  -target arm64-apple-macos15.2 myUpscaler/Processing/SourceVideoTiming.swift \
  tests/apple-api/SourceVideoTimingRegression.swift -o "$TEST_DIR/SourceVideoTimingRegression"
"$TEST_DIR/SourceVideoTimingRegression" "$TEST_DIR"
