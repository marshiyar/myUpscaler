#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -O -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 \
  -strict-concurrency=complete -warnings-as-errors -module-cache-path "$work/cache" \
  myUpscaler/Processing/ProgressUpdateGate.swift tests/logging/ProgressGateTests.swift -o "$work/test"
"$work/test"
