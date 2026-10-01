#!/bin/bash
set -euo pipefail

# An inherit-sandbox helper must be launched by a sandboxed parent, not the CI
# shell. Test a copy of the packaged bundle, keeping the helper bytes/signature
# unchanged while replacing only the GUI executable with a small launcher.
app=$1
repo_dir=$(cd "$(dirname "$0")/.." && pwd)
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
probe_app="$work_dir/FFmpeg Verification.app"
ditto "$app" "$probe_app"
cat > "$work_dir/probe.c" <<'C'
#include "up60p.h"
#include <stdio.h>
extern int execute_ffmpeg_command(char *const argv[]);
static void log_message(const char *message) { fputs(message, stdout); }
int main(void) {
    if (up60p_init(NULL, log_message) != UP60P_OK) return 1;
    char *args[] = {(char *)up60p_bundled_ffmpeg_path(), "-version", NULL};
    int result = execute_ffmpeg_command(args);
    up60p_shutdown();
    return result == 0 ? 0 : 1;
}
C
xcrun clang -std=gnu11 -D_XOPEN_SOURCE=700 -I "$repo_dir/myUpscaler/upscaler" \
  "$work_dir/probe.c" "$repo_dir/myUpscaler/up60p_restore_beast_main.c" \
  "$repo_dir/myUpscaler/up60p_settings.c" "$repo_dir/myUpscaler/up60p_utils.c" \
  "$repo_dir/myUpscaler/upscaler/up60p_process.c" -pthread -lm \
  -o "$probe_app/Contents/MacOS/myUpscaler"
cat > "$work_dir/probe.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements "$work_dir/probe.entitlements" "$probe_app"
cmp "$app/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg" \
    "$probe_app/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg"
cmp "$app/Contents/MacOS/up60p-ffmpeg-supervisor" \
    "$probe_app/Contents/MacOS/up60p-ffmpeg-supervisor"
codesign --verify --strict "$probe_app"
"$probe_app/Contents/MacOS/myUpscaler"
