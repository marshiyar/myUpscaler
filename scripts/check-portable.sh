#!/bin/bash
# Checks that need no macOS tools: source budget, then format, lint and tests for backend and desktop.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v python3 >/dev/null 2>&1 && python3 -c '' >/dev/null 2>&1; then
  py=python3
elif command -v python >/dev/null 2>&1; then
  py=python
else
  echo "FAIL: python or python3 is required" >&2
  exit 1
fi

step() {
  echo "==> $*"
  "$@" || { echo "FAIL: $*" >&2; exit 1; }
}

step "$py" scripts/check-source-budget.py
for crate in backend desktop; do
  cd "$crate"
  step cargo fmt --check
  step cargo clippy --all-targets -- -D warnings
  step cargo test
  cd ..
done
echo "PASS portable checks"
