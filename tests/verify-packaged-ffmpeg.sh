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
#include "up60p_ffmpeg_path.h"
#include <mach-o/dyld.h>
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
int main(void) {
    char executable[PATH_MAX], ffmpeg[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0 ||
        !up60p_resolve_bundled_ffmpeg(executable, ffmpeg, sizeof(ffmpeg))) return 1;
    char *args[] = {ffmpeg, "-version", NULL};
    pid_t child;
    int result = posix_spawn(&child, ffmpeg, NULL, NULL, args, environ);
    if (result != 0) { fprintf(stderr, "posix_spawn: %s\n", strerror(result)); return 1; }
    int status;
    if (waitpid(child, &status, 0) < 0) return 1;
    if (WIFSIGNALED(status)) {
        fprintf(stderr, "Bundled FFmpeg terminated by signal %d\n", WTERMSIG(status));
        return 128 + WTERMSIG(status);
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
C
xcrun clang -D_XOPEN_SOURCE=700 -I "$repo_dir/myUpscaler/upscaler" \
  "$work_dir/probe.c" -o "$probe_app/Contents/MacOS/myUpscaler"
cat > "$work_dir/probe.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/></dict></plist>
PLIST
codesign --force --sign - --entitlements "$work_dir/probe.entitlements" "$probe_app"
cmp "$app/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg" \
    "$probe_app/Contents/MacOS/ThirdParty/FFmpeg/ffmpeg"
codesign --verify --strict "$probe_app"
"$probe_app/Contents/MacOS/myUpscaler"
