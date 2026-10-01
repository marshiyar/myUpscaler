#!/bin/bash
set -euo pipefail
macos_dir="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}"
ffmpeg="$macos_dir/ThirdParty/FFmpeg/ffmpeg"
supervisor="$macos_dir/up60p-ffmpeg-supervisor"
entitlements="${PROJECT_DIR}/myUpscaler/FFmpeg.entitlements"
if [[ ! -f "$ffmpeg" ]]; then
  echo 'error: Bundled FFmpeg is missing. Run bash scripts/prepare-bundled-ffmpeg.sh before building.' >&2
  exit 1
fi
xcrun clang -std=c11 -arch arm64 \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" -isysroot "$SDKROOT" \
  -I "${PROJECT_DIR}/myUpscaler/upscaler" \
  "${PROJECT_DIR}/scripts/up60p-ffmpeg-supervisor.c" -o "$supervisor"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for executable in "$ffmpeg" "$supervisor"; do
  if [[ $(xcrun lipo -archs "$executable") != arm64 ]]; then
    echo "error: Bundled helper must contain only arm64: $executable" >&2
    exit 1
  fi
  chmod +x "$executable"
  if [[ "$identity" = - ]]; then
    codesign --force --sign - --entitlements "$entitlements" --options runtime "$executable"
  else
    codesign --force --sign "$identity" --entitlements "$entitlements" --options runtime --timestamp "$executable"
  fi
  codesign --verify --strict "$executable"
done
