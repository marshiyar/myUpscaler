#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos15.2 -strict-concurrency=complete -warnings-as-errors -default-isolation MainActor -module-cache-path "$work/cache" \
 myUpscaler/State/AppCommand.swift myUpscaler/State/KeyboardShortcutsManager.swift \
 myUpscaler/Views/KeyboardShortcutsView.swift myUpscaler/Views/DesignSystem.swift \
 myUpscaler/Views/ContentView/ContentViewConstants.swift tests/shortcuts/Tests.swift -o "$work/tests"
"$work/tests"
