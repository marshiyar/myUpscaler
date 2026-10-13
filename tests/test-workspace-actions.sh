#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R myUpscaler "$work/myUpscaler"
cp -R tests "$work/source-tests"
cd "$work"
sources=()
while IFS= read -r -d '' source; do
  sources+=("$source")
done < <(find myUpscaler -type f -name '*.swift' \
  ! -path '*/App/*' ! -name 'Up60PEngine.swift' -print0)
if (( ${#sources[@]} == 0 )); then
  echo 'No Swift sources found.' >&2
  exit 1
fi
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -module-cache-path "$work/cache" \
 "${sources[@]}" source-tests/processing-lifecycle/TestSupport.swift source-tests/workspace-actions/Tests.swift -o "$work/tests"
"$work/tests"
