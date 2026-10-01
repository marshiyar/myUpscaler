#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc "${PROCESSING_TEST_OPTIMIZATION:--O}" -parse-as-library -swift-version 5 -default-isolation MainActor \
  -module-cache-path "$work/ModuleCache" \
  myUpscaler/Processing/UpscaleRunner.swift myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
  myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols,FFmpegParser,ProcessingErrors}.swift \
  myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
  tests/processing-lifecycle/{TestSupport,LegacyBlend,Tests}.swift -o "$work/tests"
"$work/tests"
