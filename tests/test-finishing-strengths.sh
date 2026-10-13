#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
macos="$work/FinishingTests.app/Contents/MacOS"
mkdir -p "$macos/ThirdParty/FFmpeg" "$work/objects"
# Resolver fixture only: production dry-run never executes this file.
printf '#!/bin/sh\nexit 99\n' > "$macos/ThirdParty/FFmpeg/ffmpeg"
chmod +x "$macos/ThirdParty/FFmpeg/ffmpeg"
for source in myUpscaler/Native/{up60p_restore_beast_main,up60p_settings,up60p_utils}.c myUpscaler/Native/Process/up60p_process.c; do
  xcrun clang -target arm64-apple-macos15.2 -O2 -std=gnu11 -D_XOPEN_SOURCE=700 -Wall -Wextra -Werror -I myUpscaler/Native/Process -c "$source" -o "$work/objects/$(basename "$source" .c).o"
done
xcrun swiftc -O -whole-module-optimization -parse-as-library -swift-version 5 -default-isolation MainActor -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors \
 -Xlinker -fatal_warnings -module-cache-path "$work/cache" -import-objc-header myUpscaler/Native/Process/Up60PBridging.h \
 myUpscaler/Processing/{Up60PEngine,SourceVideoTiming}.swift \
 myUpscaler/State/{UpscaleSettings,PresetStore}.swift myUpscaler/State/Settings*.swift \
 myUpscaler/Models/{CoreMLModelRegistry,UpscalingModeSupport}.swift myUpscaler/Support/{CodecSupport,Protocols}.swift \
 tests/finishing-strengths/Tests.swift "$work"/objects/*.o -o "$macos/FinishingTests"
"$macos/FinishingTests"
