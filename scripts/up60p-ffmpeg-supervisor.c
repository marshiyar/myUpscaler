#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <time.h>
#include <sys/wait.h>
#include "up60p_ffmpeg_path.h"
#include "up60p_spawn.h"
#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

extern char **environ;
static volatile sig_atomic_t stop_requested = 0;
static void request_stop(int signal_number) { (void)signal_number; stop_requested = 1; }

/* Only a registered 0700 directory created by the native Neo pipeline can be
 * cleaned after owner EOF. Hold its inode open; remove only fixed owned names.
 * Ordinary FFmpeg invocations do not register any cleanup directory. */
static int owned_directory(const char *path, struct stat *identity) {
    char resolved[PATH_MAX];
    const char *name = strrchr(path, '/');
    const char *suffix = NULL;
    if (name) {
        const char *next = name;
        while ((next = strstr(next, ".neo-"))) { suffix = next; next += 5; }
    }
    if (!suffix || strlen(suffix + 5) != 6 || !realpath(path, resolved) || strcmp(path, resolved)) return -1;
    int directory = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (directory < 0) return -1;
    if (fstat(directory, identity) || !S_ISDIR(identity->st_mode) || identity->st_uid != geteuid() ||
        (identity->st_mode & 0777) != 0700) { close(directory); return -1; }
    return directory;
}
static void cleanup_owned_directory(int directory, const char *path, const struct stat *identity) {
    const char *names[] = {"input.nut", "processed.nut", "colors.txt", "final.mp4", "final.png"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) unlinkat(directory, names[i], 0);
    struct stat current;
    if (!lstat(path, &current) && current.st_dev == identity->st_dev && current.st_ino == identity->st_ino)
        rmdir(path);
}

static long long milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
    char executable[PATH_MAX], ffmpeg[PATH_MAX];
    int cleanup_directory = -1;
    const char *cleanup_path = NULL;
    struct stat cleanup_identity = {0};
    if (argc >= 3 && !strcmp(argv[1], "--owned-neo-job")) {
        cleanup_path = argv[2];
        cleanup_directory = owned_directory(cleanup_path, &cleanup_identity);
        if (cleanup_directory < 0) return 126;
        argv += 2; argc -= 2;
    }
#ifdef __APPLE__
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) != 0) return 126;
#else
    ssize_t size = readlink("/proc/self/exe", executable, sizeof(executable) - 1);
    if (size < 0) return 126;
    executable[size] = '\0';
#endif
#ifdef UP60P_NEO_SUPERVISOR
    if (!up60p_resolve_bundled_executable(executable, "up60p-neo-media", ffmpeg, sizeof(ffmpeg))) return 126;
#else
    if (!up60p_resolve_bundled_ffmpeg(executable, ffmpeg, sizeof(ffmpeg))) return 126;
#endif
    struct sigaction action = {0};
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    signal(SIGPIPE, SIG_IGN);

    posix_spawnattr_t attributes;
    int error = up60p_native_spawn_attributes(&attributes);
    if (error) return 126;
    posix_spawn_file_actions_t files;
    error = posix_spawn_file_actions_init(&files);
    if (error) { posix_spawnattr_destroy(&attributes); return 126; }
    error = posix_spawn_file_actions_addopen(&files, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (!error) error = posix_spawn_file_actions_adddup2(&files, STDOUT_FILENO, STDOUT_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&files, STDERR_FILENO, STDERR_FILENO);
    pid_t child = 0;
    argv[0] = ffmpeg;
    (void)argc;
    if (!error) error = posix_spawn(&child, ffmpeg, &files, &attributes, argv, environ);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attributes);
    if (error) {
#ifdef UP60P_NEO_SUPERVISOR
        fprintf(stderr, "Genuine Neo F3kdb spawn failed: %s\n", strerror(error));
#else
        fprintf(stderr, "Bundled FFmpeg spawn failed: %s\n", strerror(error));
#endif
        return 126;
    }

    bool stopping = false;
    bool owner_disappeared = false;
    long long deadline = 0;
    for (;;) {
        siginfo_t info = {0};
        int observed = waitid(P_PID, child, &info, WEXITED | WNOHANG | WNOWAIT);
        if (observed < 0 && errno != EINTR) {
            kill(-child, SIGKILL);
            while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
            return 126;
        }
        if (observed == 0 && info.si_pid == child) {
            /* Keep the PID reserved until group cleanup, then reap our child. */
            kill(-child, SIGKILL);
            int status;
            while (waitpid(child, &status, 0) < 0) { if (errno != EINTR) return 126; }
            if (cleanup_directory >= 0) {
                if (owner_disappeared) cleanup_owned_directory(cleanup_directory, cleanup_path, &cleanup_identity);
                close(cleanup_directory);
            }
            if (stopping) return 125;
            return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
        }
        struct pollfd owner = {STDIN_FILENO, POLLIN | POLLHUP, 0};
        int ready = poll(&owner, 1, 50);
        bool owner_gone = (ready < 0 && errno != EINTR) || (owner.revents & POLLNVAL);
        if (ready > 0 && (owner.revents & (POLLIN | POLLHUP | POLLERR))) {
            char byte;
            owner_gone = read(STDIN_FILENO, &byte, 1) == 0;
        }
        if (!stopping && (stop_requested || owner_gone)) {
            stopping = true;
            owner_disappeared = owner_gone;
            deadline = milliseconds() + 1000;
            kill(-child, SIGTERM);
        }
        if (stopping && milliseconds() >= deadline) kill(-child, SIGKILL);
    }
}
