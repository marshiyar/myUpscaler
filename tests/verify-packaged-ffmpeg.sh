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
#include <string.h>
#include <stdatomic.h>
#include <pthread.h>
#include <time.h>
#include "up60p_process.h"
extern int execute_ffmpeg_command(char *const argv[]);
static atomic_bool render_started = false;
static void log_message(const char *message) {
    fputs(message, stdout);
    if (strstr(message, "frame=")) atomic_store(&render_started, true);
}
static void *cancel_render(void *unused) {
    (void)unused;
    struct timespec pause = {0, 10000000};
    for (int i = 0; i < 500 && !atomic_load(&render_started); i++) nanosleep(&pause, NULL);
    up60p_request_cancel();
    return NULL;
}
int main(void) {
    if (up60p_init(NULL, log_message) != UP60P_OK) return 1;
    char *args[] = {(char *)up60p_bundled_ffmpeg_path(), "-version", NULL};
    int result = execute_ffmpeg_command(args);
    if (result != 0) return 1;
    char *render[] = {(char *)up60p_bundled_ffmpeg_path(), "-nostdin", "-hide_banner",
        "-loglevel", "error", "-progress", "pipe:1", "-f", "lavfi", "-i",
        "color=size=16x16:rate=1", "-f", "null", "-", NULL};
    pthread_t controller;
    if (pthread_create(&controller, NULL, cancel_render, NULL) != 0) return 1;
    result = execute_ffmpeg_command(render);
    pthread_join(controller, NULL);
    up60p_shutdown();
    if (!atomic_load(&render_started) || result != UP60P_PROCESS_CANCELLED) {
        fprintf(stderr, "Sandboxed FFmpeg cancellation failed: %d\n", result);
        return 1;
    }
    puts("Sandboxed bundled FFmpeg render and cancellation passed.");
    return 0;
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
python3 - "$probe_app/Contents/MacOS/myUpscaler" <<'PYTEST'
import subprocess, sys
subprocess.run([sys.argv[1]], check=True, timeout=20)
PYTEST
