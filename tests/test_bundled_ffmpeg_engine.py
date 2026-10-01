"""Test the production C initialization and execution path.

On Linux only, adapt dyld's executable-path lookup to /proc/self/exe. The
resolver, initialization, and child execution are the actual app C sources.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BundledFFmpegEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        folder = Path(cls.build.name)
        include_flags = []
        if sys.platform == "linux":
            headers = folder / "mach-o"
            headers.mkdir()
            (headers / "dyld.h").write_text('''
#include <stdint.h>
#include <unistd.h>
static inline int _NSGetExecutablePath(char *buffer, uint32_t *size) {
    ssize_t n = readlink("/proc/self/exe", buffer, *size - 1);
    if (n < 0 || (uint32_t)n >= *size - 1) return -1;
    buffer[n] = 0;
    return 0;
}
''')
            include_flags = ["-I", str(folder)]
        source = folder / "engine.c"
        source.write_text('''
#include "up60p.h"
#include <stdio.h>
#include <string.h>
extern int execute_ffmpeg_command(char *const argv[]);
static void log_message(const char *message) { fputs(message, stdout); }
int main(int argc, char **argv) {
    up60p_error status = up60p_init(NULL, log_message);
    if (status != UP60P_OK) return status;
    const char *path = up60p_bundled_ffmpeg_path();
    if (argc > 1 && strcmp(argv[1], "remove") == 0) {
        remove(path);
        up60p_options opts;
        up60p_default_options(&opts);
        return up60p_process_path("unused.png", &opts);
    }
    char *args[] = {(char *)(argc > 1 ? argv[1] : path), "-version", NULL};
    return execute_ffmpeg_command(args) == 0 ? 0 : 99;
}
''')
        cls.engine = folder / "engine"
        subprocess.run([os.environ.get("CC", "cc"), "-std=gnu11", "-D_XOPEN_SOURCE=700",
                        *include_flags, "-I", str(ROOT / "myUpscaler/upscaler"),
                        str(source), str(ROOT / "myUpscaler/up60p_restore_beast_main.c"),
                        str(ROOT / "myUpscaler/up60p_settings.c"),
                        str(ROOT / "myUpscaler/up60p_utils.c"), "-lm", "-o", str(cls.engine)],
                       check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        macos = self.root / "Test App.app/Contents/MacOS"
        macos.mkdir(parents=True)
        self.executable = macos / "myUpscaler"
        shutil.copy2(self.engine, self.executable)
        self.bundled = macos / "ThirdParty/FFmpeg/ffmpeg"
        self.bundled.parent.mkdir(parents=True)
        self.external = self.root / "user-bin/ffmpeg"
        self.external.parent.mkdir()
        self.external.write_text("#!/bin/sh\necho EXTERNAL_EXECUTED >&2\nexit 0\n")
        self.external.chmod(0o755)

    def install_bundle(self):
        self.bundled.write_text("#!/bin/sh\necho BUNDLED_EXECUTED >&2\nexit 0\n")
        self.bundled.chmod(0o755)

    def run_engine(self, *args):
        environment = dict(os.environ, PATH=str(self.external.parent),
                           UP60P_FFMPEG=str(self.external))
        return subprocess.run([str(self.executable), *args], env=environment,
                              capture_output=True, text=True)

    def test_executes_bundle_ignoring_override_and_path(self):
        self.install_bundle()
        result = self.run_engine()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("BUNDLED_EXECUTED", result.stdout)
        self.assertNotIn("EXTERNAL_EXECUTED", result.stdout)

    def test_missing_bundle_returns_ffmpeg_not_found(self):
        result = self.run_engine()
        self.assertEqual(result.returncode, 2)  # UP60P_ERR_FFMPEG_NOT_FOUND
        self.assertIn("Bundled FFmpeg is missing", result.stdout)

    def test_external_execution_argument_is_rejected(self):
        self.install_bundle()
        result = self.run_engine(str(self.external))
        self.assertEqual(result.returncode, 99)
        self.assertNotIn("EXTERNAL_EXECUTED", result.stdout)

    def test_bare_command_never_searches_path(self):
        self.install_bundle()
        result = self.run_engine("ffmpeg")
        self.assertEqual(result.returncode, 99)
        self.assertNotIn("EXTERNAL_EXECUTED", result.stdout)

    def test_process_revalidates_after_initialization(self):
        self.install_bundle()
        self.assertEqual(self.run_engine("remove").returncode, 2)

    def test_external_symlink_fails_initialization(self):
        self.bundled.symlink_to(self.external)
        self.assertEqual(self.run_engine().returncode, 2)


if __name__ == "__main__":
    unittest.main()
