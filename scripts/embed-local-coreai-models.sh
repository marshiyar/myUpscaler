#!/bin/bash
set -euo pipefail
# Explicit private local opt-in; assets remain separate from Core ML resources.
[[ -n "${UP60P_PRIVATE_COREAI_MODELS:-}" ]] || exit 0
resources="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
for model in "$UP60P_PRIVATE_COREAI_MODELS"/*.aimodel; do
  [[ -d "$model" ]] || continue
  name=$(basename "$model")
  [[ "$name" = RealESRGAN_CoreAI_*.aimodel ]] || { echo 'error: Unexpected private Core AI asset name' >&2; exit 1; }
  rm -rf "$resources/$name"
  ditto "$model" "$resources/$name"
done
