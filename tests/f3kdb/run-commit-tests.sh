#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
native=myUpscaler/Native
flags=(-std=c11 -arch arm64 -Wall -Wextra -Werror -O2 -I "$native" -I "$native/Process")
case "${NEO_COMMIT_SANITIZER:-}" in
  asan) flags+=(-fsanitize=address -fno-omit-frame-pointer) ;;
  ubsan) flags+=(-fsanitize=undefined -fno-sanitize-recover=all -fno-omit-frame-pointer) ;;
  "") ;;
  *) echo 'Unknown NEO_COMMIT_SANITIZER' >&2; exit 1 ;;
esac
xcrun clang "${flags[@]}" -Drename=controlled_rename -c "$native/up60p_utils.c" -o "$work/utils.o"
xcrun clang "${flags[@]}" tests/f3kdb/CommitBoundaryTests.c "$work/utils.o" -Wl,-fatal_warnings -o "$work/tests"
"$work/tests"
