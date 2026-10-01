#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -whole-module-optimization -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -O -parse-as-library -swift-version 5 -target arm64-apple-macos15.2 \
  -module-cache-path "$work/module-cache" \
  myUpscaler/Processing/{UpscaleGeometry,VideoIO}.swift \
  tests/apple-api/UpscaleOrientationRegression.swift -o "$work/orientation-tests"
"$work/orientation-tests" "$work"
