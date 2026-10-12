#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include "up60p_process.h"
#include "up60p_spawn.h"
#include "../up60p_utils.h"

extern char **environ;
static pthread_mutex_t execution_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t state_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t stopped = PTHREAD_COND_INITIALIZER;
static pid_t active_supervisor = 0;
static bool shutting_down = false;

static void close_pipe(int pipe_fds[2]) {
    for (int i = 0; i < 2; i++) if (pipe_fds[i] >= 0) { close(pipe_fds[i]); pipe_fds[i] = -1; }
}

static int owned_pipe(int fds[2]) {
    if (pipe(fds) != 0) return -1;
    for (int i = 0; i < 2; i++) {
        if (fcntl(fds[i], F_SETFD, FD_CLOEXEC) < 0) { close_pipe(fds); return -1; }
    }
    return 0;
}

void up60p_cancel_active_process(void) {
    pthread_mutex_lock(&state_lock);
    if (active_supervisor > 0) kill(active_supervisor, SIGTERM);
    pthread_mutex_unlock(&state_lock);
}

void up60p_stop_processes(void) {
    pthread_mutex_lock(&state_lock);
    shutting_down = true;
    if (active_supervisor > 0) kill(active_supervisor, SIGTERM);
    while (active_supervisor > 0) pthread_cond_wait(&stopped, &state_lock);
    pthread_mutex_unlock(&state_lock);
}

int up60p_execute_owned_process(const char *supervisor, char *const argv[], up60p_log_callback callback) {
    if (pthread_mutex_trylock(&execution_lock) != 0) return -1;
    int owner[2] = {-1, -1}, output[2] = {-1, -1}, errors[2] = {-1, -1};
    int result = -1;
    size_t count = 0;
    while (count < 512 && argv[count]) count++;
    if (count == 512) goto cleanup;
    char **arguments = calloc(count + 1, sizeof(*arguments));
    if (!arguments) goto cleanup;
    arguments[0] = (char *)supervisor;
    for (size_t i = 1; i < count; i++) arguments[i] = argv[i];
    if (owned_pipe(owner) != 0 || owned_pipe(output) != 0 || owned_pipe(errors) != 0) goto free_arguments;

    posix_spawnattr_t attributes;
    if (up60p_native_spawn_attributes(&attributes) != 0) goto free_arguments;
    posix_spawn_file_actions_t files;
    if (posix_spawn_file_actions_init(&files) != 0) { posix_spawnattr_destroy(&attributes); goto free_arguments; }
    int error = posix_spawn_file_actions_adddup2(&files, owner[0], STDIN_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&files, output[1], STDOUT_FILENO);
    if (!error) error = posix_spawn_file_actions_adddup2(&files, errors[1], STDERR_FILENO);
    pid_t child = 0;
    pthread_mutex_lock(&state_lock);
    if (shutting_down || up60p_is_cancelled()) { result = UP60P_PROCESS_CANCELLED; error = ECANCELED; }
    if (!error) error = posix_spawn(&child, supervisor, &files, &attributes, arguments, environ);
    if (!error) active_supervisor = child;
    pthread_mutex_unlock(&state_lock);
    posix_spawn_file_actions_destroy(&files);
    posix_spawnattr_destroy(&attributes);
    if (error) goto free_arguments;
    close(owner[0]); owner[0] = -1;
    close(output[1]); output[1] = -1;
    close(errors[1]); errors[1] = -1;
    fcntl(output[0], F_SETFL, O_NONBLOCK);
    fcntl(errors[0], F_SETFL, O_NONBLOCK);

    int status = 0;
    bool finished = false;
    while (!finished) {
        struct pollfd streams[2] = {{output[0], POLLIN, 0}, {errors[0], POLLIN, 0}};
        poll(streams, 2, 50);
        for (int i = 0; i < 2; i++) {
            if (streams[i].revents & (POLLIN | POLLHUP)) {
                char buffer[4096];
                for (int reads = 0; reads < 32; reads++) {
                    ssize_t n = read(streams[i].fd, buffer, sizeof(buffer) - 1);
                    if (n <= 0) {
                        if (n == 0) {
                            if (i == 0) { close(output[0]); output[0] = -1; }
                            else { close(errors[0]); errors[0] = -1; }
                        }
                        break;
                    }
                    buffer[n] = '\0';
                    if (callback) callback(buffer);
                }
            }
        }
        pthread_mutex_lock(&state_lock);
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child || (waited < 0 && errno != EINTR)) {
            finished = true;
            active_supervisor = 0;
            pthread_cond_broadcast(&stopped);
            result = waited == child && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
        }
        pthread_mutex_unlock(&state_lock);
    }
    if (result == 125 || up60p_is_cancelled()) result = UP60P_PROCESS_CANCELLED;
free_arguments:
    free(arguments);
cleanup:
    close_pipe(owner);
    close_pipe(output);
    close_pipe(errors);
    pthread_mutex_unlock(&execution_lock);
    return result;
}
