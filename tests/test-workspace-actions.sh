#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp -R myUpscaler "$work/myUpscaler"
cp -R tests "$work/source-tests"
cd "$work"
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files myUpscaler -g '*.swift' | rg -v '/App/|Up60PEngine.swift')
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -module-cache-path "$work/cache" \
 "${sources[@]}" source-tests/processing-lifecycle/TestSupport.swift source-tests/workspace-actions/Tests.swift -o "$work/tests"
"$work/tests"
