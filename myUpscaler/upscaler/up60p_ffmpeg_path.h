#ifndef UP60P_FFMPEG_PATH_H
#define UP60P_FFMPEG_PATH_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <limits.h>

/* Resolve only the executable shipped inside the running .app. Neither PATH
 * nor environment overrides participate. Reject links escaping the bundle. */
static inline bool up60p_resolve_bundled_ffmpeg(const char *executable,
                                               char *output, size_t capacity) {
    char executable_path[PATH_MAX];
    char candidate[PATH_MAX];
    char resolved[PATH_MAX];
    struct stat st;
    if (!output || capacity == 0) return false;
    output[0] = '\0';
    if (!executable || !realpath(executable, executable_path)) return false;
    char *name = strrchr(executable_path, '/');
    if (!name) return false;
    *name = '\0';
    const char suffix[] = ".app/Contents/MacOS";
    size_t length = strlen(executable_path);
    if (length < sizeof(suffix) - 1 ||
        strcmp(executable_path + length - (sizeof(suffix) - 1), suffix) != 0) {
        return false;
    }
    int written = snprintf(candidate, sizeof(candidate),
                           "%s/ThirdParty/FFmpeg/ffmpeg", executable_path);
    if (written < 0 || (size_t)written >= sizeof(candidate) ||
        !realpath(candidate, resolved) || strcmp(candidate, resolved) != 0 ||
        stat(resolved, &st) != 0 || !S_ISREG(st.st_mode) ||
        access(resolved, X_OK) != 0 || strlen(resolved) >= capacity) {
        return false;
    }
    memcpy(output, resolved, strlen(resolved) + 1);
    return true;
}

#endif
