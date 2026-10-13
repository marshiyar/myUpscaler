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
  -Wall -Wextra -Werror \
  -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" -isysroot "$SDKROOT" \
  -I "${PROJECT_DIR}/myUpscaler/Native/Process" \
  "${PROJECT_DIR}/scripts/up60p-ffmpeg-supervisor.c" -o "$supervisor"
identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
executables=("$ffmpeg" "$supervisor")
if [[ -n "${UP60P_PRIVATE_NEO_SOURCE:-}" ]]; then
  # Explicit opt-in for local evaluation only; no download or shipped cache.
  neo_work=$(mktemp -d "${DERIVED_FILE_DIR}/private-neo-XXXXXX")
  trap 'rm -rf "$neo_work"' EXIT
  python3 "${PROJECT_DIR}/scripts/f3kdb/build.py" --source "$UP60P_PRIVATE_NEO_SOURCE" --output "$neo_work" \
    --deployment-target 27.0 --sdk "$SDKROOT"
  python3 "${PROJECT_DIR}/scripts/f3kdb/bundle.py" --executable "$neo_work/up60p-neo-media" --macos "$macos_dir"
  neo_resources="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/NeoF3kdb"
  mkdir -p "$neo_resources"
  cp "$UP60P_PRIVATE_NEO_SOURCE/LICENSE" "$neo_resources/LICENSE-Neo-F3kdb"
  rm -f "$macos_dir/ThirdParty/NeoF3kdb/LICENSE-Neo-F3kdb"
  xcrun clang -std=c11 -arch arm64 -Wall -Wextra -Werror -DUP60P_NEO_SUPERVISOR=1 \
    -mmacosx-version-min="${MACOSX_DEPLOYMENT_TARGET}" -isysroot "$SDKROOT" \
    -I "${PROJECT_DIR}/myUpscaler/Native/Process" \
    "${PROJECT_DIR}/scripts/up60p-ffmpeg-supervisor.c" -o "$macos_dir/up60p-neo-supervisor"
  for library in "$macos_dir/ThirdParty/NeoF3kdb/"*.dylib; do
    codesign --force --sign "$identity" --options runtime "$library"
    codesign --verify --strict "$library"
  done
  executables+=("$macos_dir/up60p-neo-media" "$macos_dir/up60p-neo-supervisor")
else
  # Remove only this opt-in phase's owned helpers from reused derived products.
  rm -f "$macos_dir/up60p-neo-media" "$macos_dir/up60p-neo-supervisor"
  rm -rf "$macos_dir/ThirdParty/NeoF3kdb" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/NeoF3kdb"
fi
for executable in "${executables[@]}"; do
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
