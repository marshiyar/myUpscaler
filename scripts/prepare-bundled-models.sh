#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
bundle_dir="$repo_dir/third_party/CoreML"
if python3 "$repo_dir/scripts/verify-bundled-models.py" "$bundle_dir"; then
  exit 0
fi
if [[ $(uname -s) != Darwin ]]; then
  echo 'Preparing released CoreML models requires macOS and hdiutil.' >&2
  exit 1
fi

work_dir=$(mktemp -d)
mounted=0
cleanup() {
  if [[ $mounted == 1 ]]; then
    hdiutil detach "$work_dir/mount" >/dev/null || return
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT
manifest="$repo_dir/scripts/coreml-models-manifest.json"
url=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$manifest")
sha=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sha256"])' "$manifest")
curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' "$url" -o "$work_dir/models.dmg"
echo "$sha  $work_dir/models.dmg" | shasum -a 256 -c -
mkdir "$work_dir/mount" "$work_dir/models"
hdiutil attach "$work_dir/models.dmg" -readonly -nobrowse -mountpoint "$work_dir/mount"
mounted=1
# Reuse compiled models only; never launch the app from the downloaded image.
for model in RealESRGAN_x4 RealESRGAN_x8; do
  ditto "$work_dir/mount/myUpscaler.app/Contents/Resources/$model.mlmodelc" "$work_dir/models/$model.mlmodelc"
done
python3 "$repo_dir/scripts/verify-bundled-models.py" "$work_dir/models"
mkdir -p "$repo_dir/third_party"
rm -rf "$bundle_dir"
mv "$work_dir/models" "$bundle_dir"
echo "Prepared released CoreML models at $bundle_dir"
