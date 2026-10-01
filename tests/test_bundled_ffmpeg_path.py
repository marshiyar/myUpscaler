"""Exercise the production resolver against real filesystem layouts."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BundledFFmpegPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        source = Path(cls.build.name) / "resolver.c"
        source.write_text('''
#include "up60p_ffmpeg_path.h"
int main(int argc, char **argv) {
    char result[PATH_MAX];
    if (argc != 2 || !up60p_resolve_bundled_ffmpeg(argv[1], result, sizeof(result))) return 1;
    puts(result);
    return 0;
}
''')
        cls.resolver = Path(cls.build.name) / "resolver"
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-D_XOPEN_SOURCE=700",
                        "-Wall", "-Wextra", "-Werror", "-I", str(ROOT / "myUpscaler/upscaler"),
                        str(source), "-o", str(cls.resolver)], check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.macos = self.root / "My Upscaler.app/Contents/MacOS"
        self.macos.mkdir(parents=True)
        self.app_executable = self.macos / "myUpscaler"
        self.app_executable.touch()
        self.bundled = self.macos / "ThirdParty/FFmpeg/ffmpeg"
        self.bundled.parent.mkdir(parents=True)
        self.external = self.root / "user-bin/ffmpeg"
        self.external.parent.mkdir()
        self.executable(self.external)

    def executable(self, path):
        path.write_text("#!/bin/sh\nexit 0\n")
        path.chmod(0o755)

    def resolve(self, executable=None):
        environment = dict(os.environ, PATH=str(self.external.parent),
                           UP60P_FFMPEG=str(self.external))
        return subprocess.run([str(self.resolver), str(executable or self.app_executable)],
                              env=environment, capture_output=True, text=True)

    def test_uses_bundle_despite_external_environment_and_path(self):
        self.executable(self.bundled)
        result = self.resolve()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), str(self.bundled))

    def test_missing_bundle_never_falls_back_to_external_ffmpeg(self):
        self.assertEqual(self.resolve().returncode, 1)

    def test_wrong_bundle_location_is_rejected(self):
        self.executable(self.macos / "ffmpeg")
        self.assertEqual(self.resolve().returncode, 1)

    def test_non_executable_bundle_is_rejected(self):
        self.bundled.touch()
        self.bundled.chmod(0o644)
        self.assertEqual(self.resolve().returncode, 1)

    def test_directory_is_rejected(self):
        self.bundled.mkdir()
        self.assertEqual(self.resolve().returncode, 1)

    def test_symlink_to_external_ffmpeg_is_rejected(self):
        self.bundled.symlink_to(self.external)
        self.assertEqual(self.resolve().returncode, 1)

    def test_symlinked_parent_directory_is_rejected(self):
        self.bundled.parent.rmdir()
        self.bundled.parent.symlink_to(self.external.parent, target_is_directory=True)
        self.assertEqual(self.resolve().returncode, 1)

    def test_unbundled_application_is_rejected(self):
        executable = self.root / "unbundled/myUpscaler"
        executable.parent.mkdir()
        executable.touch()
        candidate = executable.parent / "ThirdParty/FFmpeg/ffmpeg"
        candidate.parent.mkdir(parents=True)
        self.executable(candidate)
        self.assertEqual(self.resolve(executable).returncode, 1)

    def test_removing_bundle_after_success_is_detected(self):
        self.executable(self.bundled)
        self.assertEqual(self.resolve().returncode, 0)
        self.bundled.unlink()
        self.assertEqual(self.resolve().returncode, 1)


if __name__ == "__main__":
    unittest.main()
