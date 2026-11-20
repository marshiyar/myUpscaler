#!/bin/bash
# Packages a release build of the desktop app with the media engine library and the licences.
#
#   bash scripts/package.sh <windows|macos|linux> <package name> <output folder>     (run from desktop/)
#
# Windows gets a .zip, the other platforms a .tar.gz; the archive holds one folder named like the package.
set -euo pipefail

platform=$1
name=$2
out=$(mkdir -p "$3" && cd "$3" && pwd)
engine=../third_party/mpvfx-media
app=target/release/myupscaler

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pkg="$work/$name"
mkdir -p "$pkg"
case $platform in
  windows) cp "$app.exe" target/release/mpvfx_ffi.dll "$pkg/" ;;
  macos) cp "$app" "$engine/lib/libmpvfx_ffi.dylib" "$pkg/" ;;
  linux) cp "$app" "$engine/lib/libmpvfx_ffi.so" "$pkg/" ;;
  *) echo "Unknown platform: $platform" >&2; exit 1 ;;
esac
cp "$engine/LICENSE" "$pkg/MpVFX-Media-LICENSE.txt"
cp "$engine/NOTICE" "$pkg/MpVFX-Media-NOTICE.txt"
cp ../LICENSE "$pkg/LICENSE.txt"

cd "$work"
if [[ $platform == windows ]]; then
  py=$(command -v python3 || command -v python)
  "$py" -m zipfile -c "$out/$name.zip" "$name"
else
  tar -czf "$out/$name.tar.gz" "$name"
fi
