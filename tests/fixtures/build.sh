#!/bin/bash
# Builds the AVFoundation test-media generator into $1 (no FFmpeg involved).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:?Pass the output executable path}
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos15.2 -module-cache-path "$(dirname "$out")/fixture-cache" \
  tests/fixtures/MakeTestMedia.swift -o "$out"
