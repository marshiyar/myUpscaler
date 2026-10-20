#!/bin/bash
# Runs test scripts at the same time, at most one per CPU core (or -j N), and prints each one's output as a group
# once all are done. Fails when any script fails. Usage: scripts/run-parallel.sh [-j N] tests/a.sh tests/b.sh ...
set -uo pipefail
cd "$(dirname "$0")/.."
max=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
if [[ ${1:-} == -j ]]; then
  max=$2
  shift 2
fi
logs=$(mktemp -d)
trap 'rm -rf "$logs"' EXIT
log() { echo "$logs/$(echo "$1" | tr '/ ' '__').log"; }
for script in "$@"; do
  # macOS ships bash 3.2 (no `wait -n`), so poll the running background jobs.
  while (( $(jobs -rp | wc -l) >= max )); do sleep 0.2; done
  # Each script records its own exit status, so the order in which they finish does not matter.
  (bash "$script" > "$(log "$script")" 2>&1; echo $? > "$(log "$script").status") &
done
wait
failed=()
for script in "$@"; do
  echo "::group::$script"
  cat "$(log "$script")"
  echo '::endgroup::'
  [[ $(cat "$(log "$script").status") == 0 ]] || failed+=("$script")
done
if (( ${#failed[@]} )); then
  for script in "${failed[@]}"; do echo "::error::$script failed"; done
  exit 1
fi
