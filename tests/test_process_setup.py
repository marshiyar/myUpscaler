"""Exercise production subprocess setup error paths without models or app builds."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProcessSetupTests(unittest.TestCase):
    def setUp(self):
        self.work = tempfile.TemporaryDirectory()
        self.addCleanup(self.work.cleanup)
        self.root = Path(self.work.name)

    def test_nonblocking_setup_failure_closes_pipes_without_spawning_and_recovers(self):
        source = self.root / "process-faults.c"
        source.write_text(r"""
#define _DARWIN_C_SOURCE 1
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
static int fail_command, fail_ordinal, matching_calls, spawn_calls;
static int tracked[6], tracked_count;
static int injected_fcntl(int fd, int command, ...) {
    int argument = 0;
    if (command == F_SETFD || command == F_SETFL) {
        va_list args; va_start(args, command);
        argument = va_arg(args, int); va_end(args);
    }
    if (command == F_SETFD && tracked_count < 6) tracked[tracked_count++] = fd;
    if (command == fail_command && ++matching_calls == fail_ordinal) {
        errno = EIO;
        return -1;
    }
    return command == F_GETFL ? fcntl(fd, command) : fcntl(fd, command, argument);
}
static int counted_spawn(pid_t *pid, const char *path,
    const posix_spawn_file_actions_t *actions, const posix_spawnattr_t *attributes,
    char *const arguments[], char *const environment[]) {
    spawn_calls++;
    return posix_spawn(pid, path, actions, attributes, arguments, environment);
}
bool up60p_is_cancelled(void) { return false; }
#define fcntl injected_fcntl
#define posix_spawn counted_spawn
#include "up60p_process.c"
#undef fcntl
#undef posix_spawn
static int no_children(void) {
    int status;
    errno = 0;
    return waitpid(-1, &status, WNOHANG) == -1 && errno == ECHILD;
}
int main(void) {
    char *arguments[] = {"/usr/bin/true", NULL};
    int commands[] = {F_GETFL, F_SETFL};
    for (int command = 0; command < 2; command++) {
        for (int ordinal = 1; ordinal <= 2; ordinal++) {
            fail_command = commands[command]; fail_ordinal = ordinal;
            matching_calls = spawn_calls = tracked_count = 0;
            if (up60p_execute_owned_process("/usr/bin/true", arguments, NULL) != -1) return 10;
            if (spawn_calls != 0 || tracked_count != 6 || !no_children()) return 11;
            for (int i = 0; i < tracked_count; i++) {
                errno = 0;
                if (fcntl(tracked[i], F_GETFD) != -1 || errno != EBADF) return 12;
            }
            fail_command = -1;
            if (up60p_execute_owned_process("/usr/bin/true", arguments, NULL) != 0) return 13;
            if (spawn_calls != 1 || !no_children()) return 14;
        }
    }
    puts("PASS four setup failures: no spawn, six pipes closed, recovery reaped");
    return 0;
}
""")
        executable = self.root / "process-faults"
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11",
                        *(["-arch", "arm64"] if sys.platform == "darwin" else []),
                        "-I", str(ROOT / "myUpscaler/upscaler"),
                        str(source), "-pthread", "-o", str(executable)], check=True)
        result = subprocess.run([str(executable)], capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS four setup failures", result.stdout)


if __name__ == "__main__":
    unittest.main()
