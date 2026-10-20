#!/bin/bash
# Downloads the MpVFX media engine (decode, H.264 encode, MP4 mux) that the Rust backend links against, verifies it
# against the pinned SHA-256 and unpacks it into third_party/mpvfx-media/{lib,include}.
#
# The engine is published as compiled releases of marshiyar/mpvfx-media-binaries; it is proprietary and shipped in
# this app by permission of its author (see LICENSE and NOTICE in the package). On macOS the arm64 package is used;
# on Linux the x86_64 package (for running the backend's tests).
set -euo pipefail

version=0.2.0
case "$(uname -s)-$(uname -m)" in
  Darwin-*)
    platform=macos-arm64
    sha256=86f44e53b9172ba60a30ae9cc8f75528efab9aab27e0f10de398420c5b3b8666
    library=libmpvfx_ffi.dylib
    ;;
  Linux-x86_64)
    platform=linux-x86_64
    sha256=980c8ae553ff8f6b0f9d420313d931c638f653615e67a72cf1dcf28fa24af12b
    library=libmpvfx_ffi.so
    ;;
  *)
    echo "No MpVFX media engine package for $(uname -s) $(uname -m)." >&2
    exit 1
    ;;
esac

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
dest="$repo_dir/third_party/mpvfx-media"
stamp="$dest/.package"
package="mpvfx-media-$version-$platform.tar.gz"

if [[ -f "$stamp" && "$(cat "$stamp")" == "$package $sha256" && -f "$dest/lib/$library" ]]; then
  echo "MpVFX media engine $version ($platform) is already prepared at $dest"
  exit 0
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
  "https://github.com/marshiyar/mpvfx-media-binaries/releases/download/media-v$version/$package" \
  -o "$work_dir/$package"
actual=$(shasum -a 256 "$work_dir/$package" 2>/dev/null || sha256sum "$work_dir/$package")
if [[ ${actual%% *} != "$sha256" ]]; then
  echo "Checksum mismatch for $package: expected $sha256, got ${actual%% *}" >&2
  exit 1
fi
mkdir -p "$work_dir/unpacked"
tar -xzf "$work_dir/$package" -C "$work_dir/unpacked" --strip-components=1
test -f "$work_dir/unpacked/lib/$library"
test -f "$work_dir/unpacked/include/mpvfx_media.h"
if [[ $platform == macos-arm64 && $(xcrun lipo -archs "$work_dir/unpacked/lib/$library") != arm64 ]]; then
  echo "The engine library must contain only arm64." >&2
  exit 1
fi
rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$work_dir/unpacked" "$dest"
echo "$package $sha256" > "$stamp"
echo "Prepared MpVFX media engine $version ($platform) at $dest"
