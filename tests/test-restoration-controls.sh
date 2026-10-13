#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -warnings-as-errors -module-cache-path "$work/cache" \
 myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/CodecSupport.swift \
 tests/restoration-controls/Tests.swift -o "$work/tests"
"$work/tests"
