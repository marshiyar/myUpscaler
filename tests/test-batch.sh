#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc "${PROCESSING_TEST_OPTIMIZATION:--O}" -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$work/ModuleCache" \
  myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan}.swift myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
  myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols,FFmpegParser,ProcessingErrors}.swift \
  myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,CoreMLModelManager,CoreAIModelWorker,CoreMLProcessingJob,CoreMLBufferAccess,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
  tests/processing-lifecycle/TestSupport.swift tests/batch/Tests.swift -o "$work/tests"
"$work/tests"
