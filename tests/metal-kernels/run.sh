#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 tests/metal-kernels/run.py --developer-dir "$(xcode-select -p)"
