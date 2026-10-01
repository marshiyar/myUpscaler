#!/bin/bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
  echo 'Preparing the macOS FFmpeg bundle requires macOS and xcrun lipo.' >&2
  exit 1
fi

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
bundle_dir="$repo_dir/myUpscaler/ThirdParty/ffmpeg"
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Same audited upstream binaries as marshiyar/mpvfx at
# fd4367d52408d772c1ff10f83015a6b2c9c91662, scripts/third_party/ffmpeg-runtime-manifest.json.
base_url=https://github.com/shaka-project/static-ffmpeg-binaries/releases/download/n8.1.2-1
for arch in arm64 x64; do
  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
    "$base_url/ffmpeg-osx-$arch" -o "$work_dir/ffmpeg-$arch"
done
(
  cd "$work_dir"
  shasum -a 256 -c <<'CHECKSUMS'
e7b9fcd97f95f333512d6e8b8ac24d9dbc08f189f36047695499bd7b57214b22  ffmpeg-arm64
62c87854d851f202fc4a29bdda0fe7b6ebcddd37b863482ce1bdc81151b03fe4  ffmpeg-x64
CHECKSUMS
)
xcrun lipo "$work_dir/ffmpeg-arm64" -verify_arch arm64
xcrun lipo "$work_dir/ffmpeg-x64" -verify_arch x86_64
xcrun lipo -create "$work_dir/ffmpeg-arm64" "$work_dir/ffmpeg-x64" -output "$work_dir/ffmpeg"
xcrun lipo "$work_dir/ffmpeg" -verify_arch arm64 x86_64
chmod +x "$work_dir/ffmpeg"
# lipo changes the binary layout, so replace any upstream ad hoc signature.
codesign --force --sign - "$work_dir/ffmpeg"
"$work_dir/ffmpeg" -version
"$work_dir/ffmpeg" -hide_banner -filters > "$work_dir/filters.txt"
if ! awk '{print $2}' "$work_dir/filters.txt" | grep -qx scale; then
  echo 'Bundled FFmpeg is missing the required Lanczos scale filter.' >&2
  exit 1
fi
for filter in sr dnn_processing zscale; do
  if ! awk '{print $2}' "$work_dir/filters.txt" | grep -qx "$filter"; then
    echo "FFmpeg $filter filter is unavailable in this bundle."
  fi
done
mkdir -p "$bundle_dir"
install -m 755 "$work_dir/ffmpeg" "$bundle_dir/ffmpeg"
echo "Prepared universal bundled FFmpeg at $bundle_dir/ffmpeg"
