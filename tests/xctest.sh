#!/bin/bash
# Runs the myUpscalerUnitTests XCTest bundle (it does not build the app) and checks the result summary.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcodebuild -project myUpscaler.xcodeproj -scheme myUpscalerUnitTests \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$work/DerivedData" \
  -resultBundlePath "$work/UnitTests.xcresult" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test 2>&1 | tail -n 200
xcrun xcresulttool get test-results summary --path "$work/UnitTests.xcresult" > "$work/summary.json"
python3 - "$work/summary.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
passed, failed = summary.get('passedTests', 0), summary.get('failedTests', 0)
assert passed >= 8 and failed == 0, summary
print(f'XCTest: {passed} passed, {failed} failed.')
PY
