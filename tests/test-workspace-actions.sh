#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sources=()
while IFS= read -r source; do sources+=("$source"); done < <(rg --files myUpscaler -g '*.swift' | rg -v '/App/|Up60PEngine.swift')
xcrun swiftc -parse-as-library -swift-version 5 -default-isolation MainActor -module-cache-path "$work/cache" \
 "${sources[@]}" tests/processing-lifecycle/TestSupport.swift tests/workspace-actions/Tests.swift -o "$work/tests"
"$work/tests"
