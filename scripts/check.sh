#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-source-budget.py
python3 -m unittest discover -s tests -p 'test_bundled_ffmpeg*.py'
bash tests/test-editor-state.sh
bash tests/test-processing-lifecycle.sh
bash tests/apple-api/run.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -module-cache-path "$work/cache" myUpscaler/Models/UpscalingModeSupport.swift \
  tests/upscaling-mode-support/main.swift -o "$work/modes"
"$work/modes"
xcodebuild -project myUpscaler.xcodeproj -scheme myUpscalerUnitTests \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/DerivedData" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
