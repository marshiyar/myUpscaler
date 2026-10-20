#!/bin/bash
# Checks a built app's processing stack: the executable links the media engine from Contents/Frameworks, the bundle
# holds no FFmpeg, and the backend's end-to-end tests pass against the packaged (signed) engine
# library.
set -euo pipefail

app=${1:?Supply the built app path}
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

executable="$app/Contents/MacOS/myUpscaler"
engine="$app/Contents/Frameworks/libmpvfx_ffi.dylib"
test -x "$executable"
test -f "$engine"
[[ $(xcrun lipo -archs "$engine") == arm64 ]]
codesign --verify --strict "$engine"
otool -L "$executable" | grep -q '@rpath/libmpvfx_ffi.dylib'
otool -l "$executable" | grep -A2 LC_RPATH | grep -q '@executable_path/../Frameworks'
nm -gU "$executable" | grep -q '_up60p_process_path'
if find "$app" -iname '*ffmpeg*' | grep -q .; then
  echo 'The app bundle still contains FFmpeg files.' >&2
  find "$app" -iname '*ffmpeg*' >&2
  exit 1
fi

# Run the backend's whole-pipeline tests against the library exactly as packaged.
mkdir -p "$work_dir/engine/lib"
cp "$engine" "$work_dir/engine/lib/"
MPVFX_MEDIA_DIR="$work_dir/engine" CARGO_TARGET_DIR="$work_dir/target" \
  cargo test --manifest-path "$repo_dir/backend/Cargo.toml" --release --test end_to_end -- --nocapture 2>&1 \
  | tee "$work_dir/test.log"
if grep -q 'skipped:' "$work_dir/test.log"; then
  echo 'The end-to-end tests did not find the packaged engine.' >&2
  exit 1
fi
echo "Verified the packaged media engine, linkage and an end-to-end render: $app"
