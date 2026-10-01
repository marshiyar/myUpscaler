#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
if ! python3 "$repo_dir/scripts/verify-bundled-models.py" "$repo_dir/third_party/CoreML"; then
  echo 'error: CoreML models are missing or invalid. Run bash scripts/prepare-bundled-models.sh before building.' >&2
  exit 1
fi
resources="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
mkdir -p "$resources"
# Remove the unsupported released x2 model from incremental builds as well.
rm -rf "$resources/RealESRGAN_x2.mlmodelc"
for model in RealESRGAN_x4 RealESRGAN_x8; do
  rm -rf "$resources/$model.mlmodelc"
  ditto "$repo_dir/third_party/CoreML/$model.mlmodelc" "$resources/$model.mlmodelc"
done
python3 "$repo_dir/scripts/verify-bundled-models.py" "$resources"
