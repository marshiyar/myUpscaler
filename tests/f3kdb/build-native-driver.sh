#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
test_macos=${1:?Pass an owned test bundle Contents/MacOS directory}
native=myUpscaler/Native
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -std=c11 -arch arm64 -O2 -Wall -Wextra -Werror \
  -mmacosx-version-min=27.0 -isysroot "$sdk" -I "$native" -I "$native/Process" \
  tests/f3kdb/native_driver.c "$native/up60p_restore_beast_main.c" \
  "$native/up60p_settings.c" "$native/up60p_utils.c" "$native/Process/up60p_process.c" \
  -pthread -lm -Wl,-fatal_warnings -o "$test_macos/native-driver"
codesign --force --sign - "$test_macos/native-driver"
codesign --verify --strict "$test_macos/native-driver"
