#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -O -parse-as-library -swift-version 5 -default-isolation MainActor \
  -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$work/cache" \
  myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan,ProgressUpdateGate}.swift \
  myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
  myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift \
  myUpscaler/Support/{VideoInput,CodecSupport,Protocols,FFmpegParser}.swift \
  tests/processing-lifecycle/TestSupport.swift tests/f3kdb/ProgressStageTests.swift -o "$work/tests"
"$work/tests"
