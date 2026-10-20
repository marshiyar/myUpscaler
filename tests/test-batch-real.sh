#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app=${1:?Pass an existing built app; no downloads are performed.}
source_app=$(cd "$source_app" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
contents="$work/BatchTests.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
for resource in "$source_app"/Contents/Resources/*.mlmodelc "$source_app/Contents/Resources/default.metallib"; do
  [[ ! -e "$resource" ]] || ln -s "$resource" "$contents/Resources/$(basename "$resource")"
done
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>BatchTests</string><key>CFBundleIdentifier</key><string>local.myUpscaler.BatchTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
source tests/rust-backend-flags.sh
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$work/cache" "${RUST_BACKEND_FLAGS[@]}" \
 myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan,Up60PEngine,SourceVideoTiming}.swift \
 myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{VideoInput,CodecSupport,Protocols,ProgressParser,ProcessingErrors}.swift \
 myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,CoreMLModelManager,CoreAIModelWorker,CoreMLProcessingJob,CoreMLBufferAccess,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
 tests/batch/RealEngineTests.swift -o "$contents/MacOS/BatchTests"
"$contents/MacOS/BatchTests" "${@:2}"
