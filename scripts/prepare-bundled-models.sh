#!/bin/bash
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
bundle_dir="$repo_dir/third_party/CoreML"
if [[ $(uname -s) != Darwin ]]; then
  echo 'Validating prebuilt CoreML models requires macOS and Xcode.' >&2
  exit 1
fi

source_dir=${COREML_MODELS_DIR:-}
archive_url=${COREML_MODEL_ARCHIVE_URL:-}
archive_sha=${COREML_MODEL_ARCHIVE_SHA256:-}
if [[ -n "$source_dir" && ( -n "$archive_url" || -n "$archive_sha" ) ]]; then
  echo 'Use either COREML_MODELS_DIR or a model archive URL/checksum, not both.' >&2
  exit 1
fi
if [[ -n "$archive_url" || -n "$archive_sha" ]]; then
  if [[ -z "$archive_url" || ! "$archive_sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo 'A model archive requires both COREML_MODEL_ARCHIVE_URL and its SHA-256 checksum.' >&2
    exit 1
  fi
fi
# Explicit inputs always take precedence over a previously prepared cache.
if [[ -z "$source_dir" && -z "$archive_url" ]] \
    && bash "$repo_dir/scripts/validate-bundled-models.sh" "$bundle_dir" --predict; then
  exit 0
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
mkdir "$work_dir/models"
if [[ -n "$archive_url" ]]; then
  # Transport checksums protect downloads; they are inputs, not fixed model identities.
  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' "$archive_url" -o "$work_dir/models.zip"
  echo "$archive_sha  $work_dir/models.zip" | shasum -a 256 -c -
  mkdir "$work_dir/archive"
  ditto -x -k "$work_dir/models.zip" "$work_dir/archive"
  source_dir="$work_dir/archive"
elif [[ -z "$source_dir" ]]; then
  # Backwards-compatible default source only. No model creation or conversion.
  url=https://github.com/marshiyar/myUpscaler/releases/download/v0.0.2-beta/MyUpscaler.dmg
  sha=7d95ec678cccf041663403753de1078f1548cc7ddd70a74f0bf1404c54a4c901
  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' "$url" -o "$work_dir/models.dmg"
  echo "$sha  $work_dir/models.dmg" | shasum -a 256 -c -
  mkdir "$work_dir/mount"
  hdiutil attach "$work_dir/models.dmg" -readonly -nobrowse -mountpoint "$work_dir/mount"
  mounted=1
  source_dir="$work_dir/mount/myUpscaler.app/Contents/Resources"
  # This particular release's x2 model needs 12 channels. A future prebuilt
  # RGB x2 supplied explicitly is accepted if its actual contract/prediction passes.
  exclude_released_x2=1
fi
model_resources=$(bash "$repo_dir/scripts/validate-bundled-models.sh" --list-resources)
while IFS= read -r model; do
  if [[ "$model" == RealESRGAN_x2 && ${exclude_released_x2:-0} == 1 ]]; then continue; fi
  if [[ -d "$source_dir/$model.mlmodelc" ]]; then
    ditto "$source_dir/$model.mlmodelc" "$work_dir/models/$model.mlmodelc"
  fi
done <<< "$model_resources"
# Test the actual model API and inference rather than any particular weights,
# tile dimensions, or undocumented compiled-model metadata format.
bash "$repo_dir/scripts/validate-bundled-models.sh" "$work_dir/models" --predict
mkdir -p "$repo_dir/third_party"
rm -rf "$bundle_dir"
mv "$work_dir/models" "$bundle_dir"
echo "Prepared validated prebuilt CoreML models at $bundle_dir"
