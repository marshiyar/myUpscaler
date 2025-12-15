#!/bin/bash
set -euo pipefail

# Copy FFmpeg dylibs from a Homebrew installation into myUpscaler/lib so
# Swift/C targets can load the bundled libraries without invoking the CLI.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEST="${REPO_ROOT}/myUpscaler/lib"

mkdir -p "$DEST"

copy_from_prefix() {
  local prefix="$1"
  local src_dir="$prefix/lib"
  if [ ! -d "$src_dir" ]; then
    return 1
  fi

  echo "Copying FFmpeg dylibs from ${src_dir}"
  shopt -s nullglob
  local copied=0
  for lib in \
    "${src_dir}/libavcodec"*.dylib \
    "${src_dir}/libavformat"*.dylib \
    "${src_dir}/libavfilter"*.dylib \
    "${src_dir}/libavutil"*.dylib \
    "${src_dir}/libavdevice"*.dylib \
    "${src_dir}/libswscale"*.dylib \
    "${src_dir}/libswresample"*.dylib; do
      cp -f "$lib" "$DEST" && copied=1
  done
  shopt -u nullglob
  return $copied
}

PREFIXES=(
  "$(brew --prefix ffmpeg 2>/dev/null || true)"
  "/opt/homebrew/opt/ffmpeg"
  "/usr/local/opt/ffmpeg"
)

success=0
for prefix in "${PREFIXES[@]}"; do
  if [ -n "$prefix" ] && copy_from_prefix "$prefix"; then
    success=1
    break
  fi
done

if [ "$success" -ne 1 ]; then
  echo "Could not locate FFmpeg dylibs. Install ffmpeg via Homebrew first." >&2
  exit 1
fi

echo "Dylibs copied to ${DEST}. Remember to embed them in the app bundle."
