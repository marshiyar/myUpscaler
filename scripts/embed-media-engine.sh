#!/bin/bash
# Xcode build phase: copies the MpVFX media engine library into Contents/Frameworks and signs it with the app's
# identity (the app links it as @rpath/libmpvfx_ffi.dylib).
set -euo pipefail

source="${PROJECT_DIR}/third_party/mpvfx-media/lib/libmpvfx_ffi.dylib"
frameworks="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
if [[ ! -f "$source" ]]; then
  echo 'error: The MpVFX media engine is missing. Run bash scripts/prepare-media-engine.sh before building.' >&2
  exit 1
fi
if [[ $(xcrun lipo -archs "$source") != arm64 ]]; then
  echo "error: The media engine library must contain only arm64: $source" >&2
  exit 1
fi
mkdir -p "$frameworks"
install -m 755 "$source" "$frameworks/libmpvfx_ffi.dylib"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ "$identity" = - ]]; then
  codesign --force --sign - --options runtime "$frameworks/libmpvfx_ffi.dylib"
else
  codesign --force --sign "$identity" --options runtime --timestamp "$frameworks/libmpvfx_ffi.dylib"
fi
codesign --verify --strict "$frameworks/libmpvfx_ffi.dylib"
