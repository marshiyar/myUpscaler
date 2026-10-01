#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
resources=${1:?Pass an existing built app Resources directory; this test never downloads models.}
resources=$(cd "$resources" && pwd)
[[ -d "$resources/RealESRGAN_x2.mlmodelc" || -d "$resources/RealESRGAN_x4.mlmodelc" ]]
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
app="$work/ModelOwnership.app/Contents"
mkdir -p "$app/MacOS" "$app/Resources"
for model in "$resources"/*.mlmodelc; do ln -s "$model" "$app/Resources/$(basename "$model")"; done
if [[ -f "$resources/default.metallib" ]]; then ln -s "$resources/default.metallib" "$app/Resources/default.metallib"; fi

cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>ModelOwnership</string><key>CFBundleIdentifier</key><string>local.myUpscaler.ModelOwnershipTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -module-cache-path "$work/cache" \
 myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan}.swift myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols,FFmpegParser,ProcessingErrors}.swift \
 myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,CoreMLModelManager,CoreMLProcessingJob,CoreMLBufferAccess,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
 tests/processing-lifecycle/{TestSupport,ModelOwnershipTests}.swift -o "$app/MacOS/ModelOwnership"
"$app/MacOS/ModelOwnership" "$(dirname "$(dirname "$resources")")"
