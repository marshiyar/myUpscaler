#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
source tests/rust-backend-flags.sh
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$work/cache" "${RUST_BACKEND_FLAGS[@]}" \
 myUpscaler/Processing/{Up60PEngine,SourceVideoTiming}.swift \
 myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols}.swift \
 tests/finishing-strengths/Tests.swift -o "$work/FinishingTests"
"$work/FinishingTests"
