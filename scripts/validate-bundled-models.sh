#!/bin/bash
set -euo pipefail
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
# Inspect compiled models through CoreML's public API, not compiler metadata
# files, fixed tile dimensions, or a manifest of particular model bytes.
xcrun swiftc "$repo_dir/myUpscaler/CoreMLModelRegistry.swift" \
  "$repo_dir/tests/packaged-models/main.swift" -o "$work_dir/model-validator"
python3 - "$work_dir/model-validator" "$@" <<'PY'
import subprocess, sys
try:
    result = subprocess.run(sys.argv[1:], timeout=600)
except subprocess.TimeoutExpired:
    sys.exit('CoreML model validation timed out.')
sys.exit(result.returncode)
PY
