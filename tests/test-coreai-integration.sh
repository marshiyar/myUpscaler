#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:?Supply the private built app}
work=${2:?Supply a fresh owned smoke-test directory}
contents="$work/Smoke.app/Contents"
mkdir -p "$contents/MacOS"
ln -s "$app/Contents/Resources" "$contents/Resources"
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>CoreAIIntegrationSmoke</string><key>CFBundleIdentifier</key><string>local.myUpscaler.CoreAIIntegrationSmoke</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$work/cache" \
 myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan}.swift myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols,FFmpegParser,ProcessingErrors}.swift \
 myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,CoreMLModelManager,CoreAIModelWorker,CoreMLProcessingJob,CoreMLBufferAccess,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
 tests/processing-lifecycle/TestSupport.swift tests/coreai-integration/Smoke.swift -o "$contents/MacOS/CoreAIIntegrationSmoke"
echo "READY $contents/MacOS/CoreAIIntegrationSmoke"
