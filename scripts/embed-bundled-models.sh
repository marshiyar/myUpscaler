#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
if ! bash "$repo_dir/scripts/validate-bundled-models.sh" "$repo_dir/third_party/CoreML"; then
  echo 'error: CoreML models are missing or invalid. Run bash scripts/prepare-bundled-models.sh before building.' >&2
  exit 1
fi
resources="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
mkdir -p "$resources"
model_resources=$(bash "$repo_dir/scripts/validate-bundled-models.sh" --list-resources)
while IFS= read -r model; do
  # Remove assets dropped from the supplied set, including legacy raw models.
  for extension in mlmodelc mlpackage mlmodel; do
    rm -rf "$resources/$model.$extension"
  done
  if [[ -d "$repo_dir/third_party/CoreML/$model.mlmodelc" ]]; then
    ditto "$repo_dir/third_party/CoreML/$model.mlmodelc" "$resources/$model.mlmodelc"
  fi
done <<< "$model_resources"
bash "$repo_dir/scripts/validate-bundled-models.sh" "$resources"
