#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$work/cache" \
 myUpscaler/State/EditorState*.swift myUpscaler/State/UpscaleSettings.swift myUpscaler/State/Settings*.swift myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/CodecSupport.swift \
 tests/editor-state/Tests.swift -o "$work/tests"
"$work/tests"
