#include "up60p_utils.h"
#include "up60p_process.h"
#include <assert.h>
#include <pthread.h>
#include <stdatomic.h>

static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static bool hold_rename, entered, release_rename, cancel_started;
static char staged[PATH_MAX], output[PATH_MAX];
static int committed_result;
static atomic_int teardown_calls;

void up60p_cancel_active_process(void) { atomic_fetch_add(&teardown_calls, 1); }

// Compile utils.c with rename=controlled_rename. This blocks exactly inside
// the filesystem operation; production code has no test hook or timing sleep.
int controlled_rename(const char *from, const char *to) {
    pthread_mutex_lock(&gate);
    if (hold_rename) {
        entered = true;
        pthread_cond_broadcast(&changed);
        while (!release_rename) pthread_cond_wait(&changed, &gate);
    }
    pthread_mutex_unlock(&gate);
    return rename(from, to);
}
static void write_text(const char *path, const char *value) {
    FILE *file = fopen(path, "w"); assert(file);
    assert(fputs(value, file) >= 0); assert(fclose(file) == 0);
}
static void expect_text(const char *path, const char *value) {
    char text[32] = {0}; FILE *file = fopen(path, "r"); assert(file);
    assert(fread(text, 1, sizeof(text)-1, file) == strlen(value));
    assert(fclose(file) == 0); assert(!strcmp(text, value));
}
static void reset_case(void) {
    up60p_reset_cancel();
    write_text(staged, "new"); write_text(output, "previous");
    hold_rename = entered = release_rename = cancel_started = false;
    atomic_store(&teardown_calls, 0);
}
static void *commit_worker(void *unused) {
    (void)unused;
    committed_result = up60p_commit_output(staged, output); return NULL;
}
static void *cancel_worker(void *unused) {
    (void)unused;
    pthread_mutex_lock(&gate);
    cancel_started = true; pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
    up60p_request_cancel(); return NULL;
}
static void release_operation(void) {
    pthread_mutex_lock(&gate);
    release_rename = true; pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
}
static void wait_for(bool *value) {
    pthread_mutex_lock(&gate);
    while (!*value) pthread_cond_wait(&changed, &gate);
    pthread_mutex_unlock(&gate);
}
// The prior orchestration separately checked cancellation, renamed, then
// prioritized cancellation again. Reproduce its false-cancel publication.
static void *old_commit_worker(void *unused) {
    (void)unused;
    int result = up60p_is_cancelled() ? UP60P_PROCESS_CANCELLED : controlled_rename(staged, output);
    committed_result = up60p_is_cancelled() ? UP60P_PROCESS_CANCELLED : result;
    return NULL;
}
int main(void) {
    char directory[] = "/tmp/neo-commit-XXXXXX"; assert(mkdtemp(directory));
    snprintf(staged, sizeof(staged), "%s/staged", directory);
    snprintf(output, sizeof(output), "%s/output", directory);
    pthread_t worker, cancellation;

    reset_case(); hold_rename = true;
    assert(!pthread_create(&worker, NULL, old_commit_worker, NULL)); wait_for(&entered);
    up60p_request_cancel(); release_operation(); assert(!pthread_join(worker, NULL));
    assert(committed_result == UP60P_PROCESS_CANCELLED); expect_text(output, "new");
    puts("REPRO: old commit replaced output but reported cancellation");

    reset_case(); up60p_request_cancel();
    assert(up60p_commit_output(staged, output) == UP60P_PROCESS_CANCELLED);
    expect_text(output, "previous"); expect_text(staged, "new");
    puts("PASS: cancellation before commit preserves both files");

    reset_case(); hold_rename = true;
    assert(!pthread_create(&worker, NULL, commit_worker, NULL)); wait_for(&entered);
    assert(!pthread_create(&cancellation, NULL, cancel_worker, NULL)); wait_for(&cancel_started);
    assert(!up60p_is_cancelled()); assert(atomic_load(&teardown_calls) == 0);
    release_operation(); assert(!pthread_join(worker, NULL)); assert(!pthread_join(cancellation, NULL));
    assert(committed_result == UP60P_PROCESS_COMMITTED); expect_text(output, "new");
    assert(up60p_is_cancelled()); assert(atomic_load(&teardown_calls) == 1);
    puts("PASS: cancellation during rename waits; committed success survives");

    reset_case(); committed_result = up60p_commit_output(staged, output);
    up60p_request_cancel();
    assert(committed_result == UP60P_PROCESS_COMMITTED); expect_text(output, "new");
    puts("PASS: cancellation after commit preserves committed success");

    reset_case(); unlink(staged);
    assert(up60p_commit_output(staged, output) == -1); expect_text(output, "previous");
    unlink(output); assert(!rmdir(directory));
    puts("PASS: rename failure preserves existing destination");
    return 0;
}
