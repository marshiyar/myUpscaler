#ifndef UP60P_SPAWN_H
#define UP60P_SPAWN_H
#include <spawn.h>
#include <signal.h>
#include <errno.h>
#ifdef __APPLE__
#include <mach/machine.h>
#endif

/* Apple Silicon only: never launch an Intel helper, including under Rosetta. */
static inline int up60p_native_spawn_attributes(posix_spawnattr_t *attributes) {
    int error = posix_spawnattr_init(attributes);
    if (error) return error;
    short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF;
#ifdef POSIX_SPAWN_CLOEXEC_DEFAULT
    flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
    sigset_t mask, defaults;
    sigemptyset(&mask);
    sigemptyset(&defaults);
    sigaddset(&defaults, SIGTERM);
    sigaddset(&defaults, SIGINT);
    sigaddset(&defaults, SIGPIPE);
    sigaddset(&defaults, SIGCHLD);
    error = posix_spawnattr_setflags(attributes, flags);
    if (!error) error = posix_spawnattr_setpgroup(attributes, 0);
    if (!error) error = posix_spawnattr_setsigmask(attributes, &mask);
    if (!error) error = posix_spawnattr_setsigdefault(attributes, &defaults);
#ifdef __APPLE__
    cpu_type_t preferred = CPU_TYPE_ARM64;
    size_t accepted = 0;
    if (!error) error = posix_spawnattr_setbinpref_np(attributes, 1, &preferred, &accepted);
    if (!error && accepted != 1) error = EINVAL;
#endif
    if (error) posix_spawnattr_destroy(attributes);
    return error;
}
#endif
