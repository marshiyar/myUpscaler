#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_app=${1:?Pass an existing built app; no downloads are performed.}
source_app=$(cd "$source_app" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
contents="$work/BatchTests.app/Contents"
mkdir -p "$contents/MacOS/ThirdParty/FFmpeg" "$contents/Resources" "$work/objects"
cp "$source_app/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg" "$contents/MacOS/ThirdParty/FFmpeg/ffmpeg"
cp "$source_app/Contents/MacOS/up60p-ffmpeg-supervisor" "$contents/MacOS/up60p-ffmpeg-supervisor"
# These helpers normally inherit the GUI app sandbox. This command-line test
# has no app sandbox to inherit, so re-sign only its disposable copies without
# entitlements. Production helpers and executable code remain unchanged.
cat > "$work/empty-entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>
PLIST
codesign --force --sign - --entitlements "$work/empty-entitlements.plist" "$contents/MacOS/ThirdParty/FFmpeg/ffmpeg" "$contents/MacOS/up60p-ffmpeg-supervisor"
for resource in "$source_app"/Contents/Resources/*.mlmodelc "$source_app/Contents/Resources/default.metallib"; do
  [[ ! -e "$resource" ]] || ln -s "$resource" "$contents/Resources/$(basename "$resource")"
done
cat > "$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>BatchTests</string><key>CFBundleIdentifier</key><string>local.myUpscaler.BatchTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
for source in myUpscaler/Native/{up60p_restore_beast_main,up60p_settings,up60p_utils}.c myUpscaler/Native/Process/up60p_process.c; do
  xcrun clang -target arm64-apple-macos15.2 -O2 -std=gnu11 -D_XOPEN_SOURCE=700 -Wall -Wextra -Werror -I myUpscaler/Native/Process -c "$source" -o "$work/objects/$(basename "$source" .c).o"
done
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -Xlinker -fatal_warnings -module-cache-path "$work/cache" -import-objc-header myUpscaler/Native/Process/Up60PBridging.h \
 myUpscaler/Processing/{UpscaleRunner,UpscaleRunner+Batch,BatchPlan,Up60PEngine,SourceVideoTiming}.swift \
 myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols,FFmpegParser,ProcessingErrors}.swift \
 myUpscaler/Processing/{CoreMLEngine,CoreMLEngine+Shaders,CoreMLModelManager,CoreMLProcessingJob,CoreMLBufferAccess,ProcessingControl,UpscaleGeometry,VideoIO,VideoAudioMuxer,ProgressUpdateGate}.swift \
 tests/batch/RealEngineTests.swift "$work"/objects/*.o -o "$contents/MacOS/BatchTests"
"$contents/MacOS/BatchTests" "${@:2}"
