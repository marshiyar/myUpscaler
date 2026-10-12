#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$work/cache" \
 myUpscaler/EditorState.swift myUpscaler/UpscaleSettings.swift myUpscaler/Models/CoreMLModelRegistry.swift myUpscaler/Support/CodecSupport.swift myUpscaler/Models/UpscalingModeSupport.swift \
 tests/editor-state/Tests.swift -o "$work/tests"
"$work/tests"
