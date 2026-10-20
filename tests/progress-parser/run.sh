#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -module-cache-path "$work/cache" myUpscaler/Support/ProgressParser.swift \
  tests/progress-parser/main.swift -o "$work/progress-parser"
"$work/progress-parser"
