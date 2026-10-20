#!/bin/bash
# Runs test scripts at the same time and prints each one's output as a group once all are done. Fails when any
# script fails. Usage: scripts/run-parallel.sh tests/a.sh tests/b.sh ...
set -uo pipefail
cd "$(dirname "$0")/.."
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
pids=()
for script in "$@"; do
  bash "$script" > "$logs/$(echo "$script" | tr '/' '_').log" 2>&1 &
  pids+=($!)
done
failed=()
for i in "${!pids[@]}"; do
  if ! wait "${pids[$i]}"; then failed+=("$1"); fi
  script=$1; shift
  echo "::group::$script"
  cat "$logs/$(echo "$script" | tr '/' '_').log"
  echo '::endgroup::'
done
if (( ${#failed[@]} )); then
  for script in "${failed[@]}"; do echo "::error::$script failed"; done
  exit 1
fi
