#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
xcrun swiftc -module-cache-path "$TEST_DIR/module-cache" -swift-version 5 \
  -target arm64-apple-macos15.2 -O \
  myUpscaler/Processing/VideoIO.swift tests/apple-api/VideoIORegression.swift \
  -o "$TEST_DIR/VideoIORegression"
"$TEST_DIR/VideoIORegression"
