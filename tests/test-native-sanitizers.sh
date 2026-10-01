#!/bin/bash
# Instrument temporary regression binaries; application build settings are untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $(uname -s) != Darwin || $(uname -m) != arm64 ]]; then
  echo 'Native sanitizer checks require an Apple Silicon Mac.' >&2
  exit 1
fi
mode="${1:-all}"
case "$mode" in all|address|thread) ;; *) echo 'Usage: bash tests/test-native-sanitizers.sh [all|address|thread]' >&2; exit 2 ;; esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cat > "$work/address-cc" <<'CC'
#!/bin/bash
exec xcrun clang -fsanitize=address,undefined -fno-omit-frame-pointer "$@"
CC
cat > "$work/thread-cc" <<'CC'
#!/bin/bash
exec xcrun clang -fsanitize=thread -fno-omit-frame-pointer "$@"
CC
chmod +x "$work/address-cc" "$work/thread-cc"
if [[ "$mode" == all || "$mode" == address ]]; then
  echo 'ASan/UBSan: full native subprocess regression suite'
  # macOS ASan does not support LeakSanitizer. Descriptor/child cleanup is tested
  # explicitly by the suite; do not silence memory or undefined-behavior reports.
  CC="$work/address-cc" UBSAN_OPTIONS=halt_on_error=1 \
    python3 -m unittest discover -s tests -p 'test_bundled_ffmpeg_engine.py'
fi
if [[ "$mode" == all || "$mode" == thread ]]; then
  echo 'TSan: ownership, reentrant/concurrent callbacks and setup-failure recovery'
  CC="$work/thread-cc" TSAN_OPTIONS=halt_on_error=1 PYTHONPATH=tests \
    python3 -m unittest \
    test_bundled_ffmpeg_engine.BundledFFmpegEngineTests.test_execution_claim_rejects_reentrant_and_concurrent_callback_jobs \
    test_bundled_ffmpeg_engine.BundledFFmpegEngineTests.test_nonblocking_setup_failure_closes_pipes_without_spawning_and_recovers
fi
