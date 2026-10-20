#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -module-cache-path "$work/cache" myUpscaler/Models/UpscalingModeSupport.swift \
  tests/upscaling-mode-support/main.swift -o "$work/modes"
"$work/modes"
