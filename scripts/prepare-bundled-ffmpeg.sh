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
curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
  "$base_url/ffmpeg-osx-arm64" -o "$work_dir/ffmpeg"
(
  cd "$work_dir"
  shasum -a 256 -c <<'CHECKSUMS'
e7b9fcd97f95f333512d6e8b8ac24d9dbc08f189f36047695499bd7b57214b22  ffmpeg
CHECKSUMS
)
if [[ $(xcrun lipo -archs "$work_dir/ffmpeg") != arm64 ]]; then
  echo 'Bundled FFmpeg must contain only arm64; Intel Macs are unsupported.' >&2
  exit 1
fi
chmod +x "$work_dir/ffmpeg"
# Apply a local ad hoc signature before checking the downloaded executable.
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
echo "Prepared arm64 bundled FFmpeg at $bundle_dir/ffmpeg"
