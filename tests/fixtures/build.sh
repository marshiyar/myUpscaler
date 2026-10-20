#!/bin/bash
# Builds the AVFoundation test-media generator into $1 (no FFmpeg involved). When MAKE_TEST_MEDIA names an already
# built generator (CI builds it once per job), that one is reused.
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:?Pass the output executable path}
if [[ -n ${MAKE_TEST_MEDIA:-} && -x $MAKE_TEST_MEDIA ]]; then
  cp "$MAKE_TEST_MEDIA" "$out"
  exit 0
fi
xcrun swiftc -O -swift-version 5 -target arm64-apple-macos15.2 -module-cache-path "$(dirname "$out")/fixture-cache" \
  tests/fixtures/MakeTestMedia.swift -o "$out"
