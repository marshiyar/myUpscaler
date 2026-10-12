#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc "${PROCESSING_TEST_OPTIMIZATION:--O}" -parse-as-library -swift-version 5 -default-isolation MainActor \
  -module-cache-path "$work/ModuleCache" \
  myUpscaler/UpscaleRunner.swift myUpscaler/UpscaleSettings.swift myUpscaler/PresetStore.swift myUpscaler/Models/CoreMLModelRegistry.swift myUpscaler/Models/UpscalingModeSupport.swift myUpscaler/Support/CodecSupport.swift myUpscaler/Support/Protocols.swift myUpscaler/Support/FFmpegParser.swift \
  myUpscaler/upscaler/{CoreMLEngine,CoreMLEngine+Shaders,ProcessingControl,UpscaleGeometry,VideoIO,ProgressUpdateGate}.swift \
  tests/processing-lifecycle/{TestSupport,LegacyBlend,Tests}.swift -o "$work/tests"
"$work/tests"
