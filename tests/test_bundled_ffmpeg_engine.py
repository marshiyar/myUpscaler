"""Test the production C initialization and execution path.

On Linux only, adapt dyld's executable-path lookup to /proc/self/exe. The
resolver, initialization, and child execution are the actual app C sources.
"""
import os
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import signal
import shlex
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BundledFFmpegEngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        folder = Path(cls.build.name)
        include_flags = []
        architecture_flags = ["-arch", "arm64", "-arch", "x86_64"] if sys.platform == "darwin" else []
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
#include <pthread.h>
#include <unistd.h>
#include <time.h>
#include "up60p_process.h"
extern int execute_ffmpeg_command(char *const argv[]);
static void log_message(const char *message) { fputs(message, stdout); }
static const char *control_mode;
static const char *ready_file;
static void *control(void *unused) {
    (void)unused;
    struct timespec pause = {0, 10000000};
    for (int i = 0; i < 500 && access(ready_file, F_OK) != 0; i++) nanosleep(&pause, NULL);
    if (strcmp(control_mode, "shutdown") == 0) up60p_shutdown();
    else up60p_request_cancel();
    return NULL;
}
int main(int argc, char **argv) {
    up60p_error status = up60p_init(NULL, log_message);
    if (status != UP60P_OK) return status;
    const char *path = up60p_bundled_ffmpeg_path();
    if (argc > 2 && (strcmp(argv[1], "cancel") == 0 || strcmp(argv[1], "shutdown") == 0)) {
        control_mode = argv[1];
        ready_file = argv[2];
        pthread_t thread;
        pthread_create(&thread, NULL, control, NULL);
        char *args[] = {(char *)path, "-version", NULL};
    int result = execute_ffmpeg_command(args);
    pthread_join(thread, NULL);
    if (argc > 3) {
        up60p_options opts;
        up60p_default_options(&opts);
        return up60p_process_path(argv[3], &opts);
    }
    return result == UP60P_PROCESS_CANCELLED ? UP60P_ERR_CANCELLED : 99;
    }
    if (argc > 6 && strcmp(argv[1], "eq") == 0) {
        up60p_options opts;
        up60p_default_options(&opts);
        snprintf(opts.eq_contrast, sizeof(opts.eq_contrast), "%s", argv[2]);
        snprintf(opts.eq_brightness, sizeof(opts.eq_brightness), "%s", argv[3]);
        snprintf(opts.eq_saturation, sizeof(opts.eq_saturation), "%s", argv[4]);
        opts.no_eq = strcmp(argv[5], "off") == 0;
        opts.no_decimate = opts.no_interpolate = true;
        opts.no_denoise = opts.no_deblock = opts.no_sharpen = true;
        opts.no_deband = opts.no_grain = true;
        snprintf(opts.fps, sizeof(opts.fps), "source");
        snprintf(opts.scale_factor, sizeof(opts.scale_factor), "1");
        return up60p_process_path(argv[6], &opts);
    }
    if (argc > 5 && strcmp(argv[1], "encoder") == 0) {
        up60p_options opts;
        up60p_default_options(&opts);
        snprintf(opts.encoder, sizeof(opts.encoder), "%s", argv[2]);
        snprintf(opts.codec, sizeof(opts.codec), "%s", argv[3]);
        opts.use10 = strcmp(argv[4], "10") == 0;
        return up60p_process_path(argv[5], &opts);
    }
    if (argc > 4 && strcmp(argv[1], "fps") == 0) {
        up60p_options opts;
        up60p_default_options(&opts);
        snprintf(opts.fps, sizeof(opts.fps), "%s", argv[2]);
        opts.no_interpolate = strcmp(argv[3], "off") == 0;
        if (strcmp(argv[3], "dup") == 0) snprintf(opts.mi_mode, sizeof(opts.mi_mode), "dup");
        opts.no_decimate = true;
        opts.no_denoise = opts.no_deblock = opts.no_sharpen = true;
        opts.no_deband = opts.no_grain = true;
        return up60p_process_path(argv[4], &opts);
    }
    if (argc > 2 && strcmp(argv[1], "scaler") == 0) {
        up60p_options opts;
        up60p_default_options(&opts);
        snprintf(opts.scaler, sizeof(opts.scaler), "%s", argv[2]);
        return up60p_process_path(argc > 3 ? argv[3] : "unused.png", &opts);
    }
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
                        *architecture_flags, *include_flags, "-I", str(ROOT / "myUpscaler/Native/Process"),
                        str(source), str(ROOT / "myUpscaler/Native/up60p_restore_beast_main.c"),
                        str(ROOT / "myUpscaler/Native/up60p_settings.c"),
                        str(ROOT / "myUpscaler/Native/up60p_utils.c"),
                        str(ROOT / "myUpscaler/Native/Process/up60p_process.c"), "-pthread", "-lm", "-o", str(cls.engine)],
                       check=True)

        cls.supervisor = folder / "up60p-ffmpeg-supervisor"
        subprocess.run([os.environ.get("CC", "cc"), "-std=c11", "-D_XOPEN_SOURCE=700",
                        *(["-arch", "arm64"] if sys.platform == "darwin" else []),
                        "-I", str(ROOT / "myUpscaler/Native/Process"),
                        str(ROOT / "scripts/up60p-ffmpeg-supervisor.c"), "-o", str(cls.supervisor)], check=True)

        if sys.platform == "darwin":
            marker_source = folder / "architecture.c"
            marker_source.write_text('''#include <stdio.h>
int main(void) {
#if defined(__arm64__)
    puts("NATIVE_ARCH=arm64");
#else
    puts("NATIVE_ARCH=x86_64");
#endif
    return 0;
}
''')
            cls.architecture_marker = folder / "architecture"
            subprocess.run(["xcrun", "clang", *architecture_flags, str(marker_source),
                            "-o", str(cls.architecture_marker)], check=True)

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
        shutil.copy2(self.supervisor, macos / "up60p-ffmpeg-supervisor")
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
                              capture_output=True, text=True, timeout=8)

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

    def test_legacy_ai_mode_is_rejected_without_execution(self):
        self.install_bundle()
        result = self.run_engine("scaler", "ai")
        self.assertEqual(result.returncode, 6)  # UP60P_ERR_UNSUPPORTED_SCALER
        self.assertIn("unsupported", result.stdout)
        self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    def test_legacy_zscale_mode_is_rejected_without_execution(self):
        self.install_bundle()
        result = self.run_engine("scaler", "zscale")
        self.assertEqual(result.returncode, 6)
        self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    def test_legacy_hardware_scaler_is_rejected_without_execution(self):
        self.install_bundle()
        result = self.run_engine("scaler", "hw")
        self.assertEqual(result.returncode, 6)
        self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    def test_unknown_scaler_does_not_silently_fall_back(self):
        self.install_bundle()
        result = self.run_engine("scaler", "unknown")
        self.assertEqual(result.returncode, 6)
        self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    def test_coreml_is_never_sent_to_the_ffmpeg_engine(self):
        self.install_bundle()
        self.assertEqual(self.run_engine("scaler", "coreml").returncode, 6)

    def test_lanczos_still_reaches_the_bundled_executable(self):
        self.install_bundle()
        image = self.root / "input.png"
        image.touch()
        result = self.run_engine("scaler", "lanczos", str(image))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("BUNDLED_EXECUTED", result.stdout)

    def capture_fps_filter(self, fps, interpolation):
        self.bundled.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        self.bundled.chmod(0o755)
        video = self.root / "input.mp4"
        video.touch()
        result = self.run_engine("fps", fps, interpolation, str(video))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_source_and_lock_never_use_default_60fps_interpolation(self):
        for fps in ("source", "lock"):
            for interpolation in ("on", "off"):
                command = self.capture_fps_filter(fps, interpolation)
                self.assertNotIn("minterpolate=", command)
                self.assertNotIn("fps=fps=", command)
                self.assertIn("-fps_mode\npassthrough", command)

    def test_numeric_fps_without_interpolation_uses_frame_selection(self):
        for fps in ("24", "30000/1001", "23.976"):
            command = self.capture_fps_filter(fps, "off")
            self.assertIn(f"fps=fps={fps},scale=", command)
            self.assertNotIn("minterpolate=", command)

    def test_duplicate_mode_uses_frame_selection_without_interpolator_latency(self):
        command = self.capture_fps_filter("60", "dup")
        self.assertIn("fps=fps=60,scale=", command)
        self.assertNotIn("minterpolate=", command)

    def test_interpolation_retains_exact_rate_and_runs_before_upscale(self):
        command = self.capture_fps_filter("60000/1001", "on")
        self.assertIn("minterpolate=fps=60000/1001:", command)
        self.assertLess(command.index("minterpolate="), command.index("scale="))

    def test_videotoolbox_encoders_receive_supported_quality_flags(self):
        self.bundled.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        self.bundled.chmod(0o755)
        video = self.root / "input.mp4"
        video.touch()
        for codec, depth in (("h264", "8"), ("hevc", "8"), ("hevc", "10")):
            result = self.run_engine("encoder", "videotoolbox", codec, depth, str(video))
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertIn(f"-c:v\n{codec}_videotoolbox", result.stdout)
            self.assertIn("-q:v\n61.18", result.stdout)
            self.assertIn("-allow_sw\n0", result.stdout)
            self.assertNotIn("-crf\n", result.stdout)
            self.assertNotIn("-preset\n", result.stdout)
            if depth == "10":
                self.assertIn("-pix_fmt\np010le", result.stdout)

    def test_videotoolbox_h264_10bit_fails_before_execution(self):
        self.install_bundle()
        video = self.root / "input.mp4"
        video.touch()
        result = self.run_engine("encoder", "videotoolbox", "h264", "10", str(video))
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Select HEVC", result.stdout)
        self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "requires local FFmpeg/ffprobe")
    def test_real_rational_fps_conversion_preserves_audio_duration(self):
        ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
        shutil.copy2(ffmpeg, self.bundled)
        video = self.root / "input.mp4"
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                        "testsrc2=size=160x90:rate=24000/1001:duration=3",
                        "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                        "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac",
                        "-y", str(video)], check=True, timeout=8)
        for fps, expected_rate, expected_frames in (("source", "24000/1001", 72),
                                                    ("30000/1001", "30000/1001", 90),
                                                    ("12", "12/1", 36)):
            result = self.run_engine("fps", fps, "off", str(video))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            output = self.root / "input_[restored].mp4"
            streams = json.loads(subprocess.check_output([ffprobe, "-v", "error",
                                 "-show_streams", "-of", "json", str(output)]))["streams"]
            v = next(item for item in streams if item["codec_type"] == "video")
            audio = next(item for item in streams if item["codec_type"] == "audio")
            self.assertEqual(v["avg_frame_rate"], expected_rate)
            self.assertEqual(int(v["nb_frames"]), expected_frames)
            self.assertLess(abs(float(v["duration"]) - float(audio["duration"])), 1 / 12)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "requires local FFmpeg/ffprobe")
    def test_real_source_mode_preserves_variable_frame_timestamps(self):
        ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
        shutil.copy2(ffmpeg, self.bundled)
        video = self.root / "input.mp4"
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                        "testsrc2=size=160x90:rate=24:duration=2", "-vf", "select=mod(n\\,3)",
                        "-fps_mode", "passthrough", "-c:v", "libx264", "-preset", "ultrafast",
                        "-y", str(video)], check=True, timeout=8)
        def timestamps(path):
            frames = json.loads(subprocess.check_output([ffprobe, "-v", "error", "-select_streams", "v:0",
                               "-show_frames", "-show_entries", "frame=best_effort_timestamp_time",
                               "-of", "json", str(path)]))["frames"]
            points = [float(frame["best_effort_timestamp_time"]) for frame in frames]
            return [point - points[0] for point in points]
        source_pts = timestamps(video)
        result = self.run_engine("fps", "source", "off", str(video))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output_pts = timestamps(self.root / "input_[restored].mp4")
        self.assertEqual(len(source_pts), len(output_pts))
        for before, after in zip(source_pts, output_pts):
            self.assertAlmostEqual(before, after, places=5)

    def test_eq_enabled_disabled_and_neutral_commands(self):
        self.bundled.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        self.bundled.chmod(0o755)
        image = self.root / "input.png"
        image.touch()
        for values, enabled in ((("1.2", "0.1", "0.8"), "on"),
                                (("1.2", "0.1", "0.8"), "off"),
                                (("1", "0", "1"), "on")):
            result = self.run_engine("eq", *values, enabled, str(image))
            self.assertEqual(result.returncode, 0, result.stdout)
            if enabled == "on" and values[0] != "1":
                self.assertIn("eq=contrast=1.2:brightness=0.1:saturation=0.8", result.stdout)
            else:
                self.assertNotIn("eq=contrast=", result.stdout)

    def test_invalid_eq_numbers_fail_before_execution(self):
        self.install_bundle()
        image = self.root / "input.png"
        image.touch()
        for value in ("nan", "inf", "1,scale=9", "2junk", "1001", ""):
            result = self.run_engine("eq", value, "0", "1", "on", str(image))
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertNotIn("BUNDLED_EXECUTED", result.stdout)

    @unittest.skipUnless(shutil.which("ffmpeg"), "requires local FFmpeg")
    def test_real_eq_changes_pixels_and_disable_matches_neutral(self):
        ffmpeg = shutil.which("ffmpeg")
        shutil.copy2(ffmpeg, self.bundled)
        image = self.root / "input.png"
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                        "color=c=0x806040:size=32x32", "-frames:v", "1", "-y", str(image)], check=True, timeout=8)
        pixels = []
        for brightness, saturation, enabled in (("0", "1", "on"), ("0.1", "1", "on"),
                                                ("0.1", "1", "off"), ("-0.1", "1", "on"),
                                                ("0", "0", "on")):
            result = self.run_engine("eq", "1", brightness, saturation, enabled, str(image))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            pixels.append(subprocess.check_output([ffmpeg, "-v", "error", "-i",
                          str(self.root / "input_[restored].png"), "-pix_fmt", "rgb24",
                          "-f", "rawvideo", "-"]))
        self.assertEqual(pixels[0], pixels[2])
        self.assertNotEqual(pixels[0], pixels[1])
        self.assertGreater(sum(pixels[1]), sum(pixels[0]))
        self.assertLess(sum(pixels[3]), sum(pixels[0]))
        self.assertNotEqual(pixels[0], pixels[4])
        self.assertLessEqual(max(pixels[4][:3]) - min(pixels[4][:3]), 4)

    def busy_bundle(self, ignore_term=False, descendant_file=None, once=False):
        pidfile = self.root / "ffmpeg.pid"
        script = "#!/bin/sh\n"
        if once:
            script += f'if [ -f {shlex.quote(str(pidfile))} ]; then echo NEXT_RUN >&2; exit 0; fi\n'
        if ignore_term:
            script += "trap '' TERM\n"
        if descendant_file:
            script += f'(while :; do :; done) &\necho $! > {shlex.quote(str(descendant_file))}\n'
        script += f'echo $$ > {shlex.quote(str(pidfile))}\nwhile :; do :; done\n'
        self.bundled.write_text(script)
        self.bundled.chmod(0o755)
        return pidfile

    def is_running(self, pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        # An orphan's zombie awaiting init's reap does not consume CPU.
        result = subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True)
        return bool(result.stdout.strip()) and not result.stdout.strip().startswith("Z")

    def assert_stopped(self, pid):
        deadline = time.monotonic() + 3
        while self.is_running(pid) and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(self.is_running(pid), f"Owned process {pid} still running")

    def test_cancel_stops_busy_ffmpeg(self):
        pidfile = self.busy_bundle()
        result = self.run_engine("cancel", str(pidfile))
        self.assertEqual(result.returncode, 5, result.stdout)
        self.assert_stopped(int(pidfile.read_text()))

    def test_shutdown_stops_busy_ffmpeg(self):
        pidfile = self.busy_bundle()
        result = self.run_engine("shutdown", str(pidfile))
        self.assertEqual(result.returncode, 5, result.stdout)
        self.assert_stopped(int(pidfile.read_text()))

    def test_cancel_escalates_when_ffmpeg_ignores_term(self):
        pidfile = self.busy_bundle(ignore_term=True)
        started = time.monotonic()
        self.assertEqual(self.run_engine("cancel", str(pidfile)).returncode, 5)
        self.assertLess(time.monotonic() - started, 4)
        self.assert_stopped(int(pidfile.read_text()))

    def test_force_quitting_app_stops_owned_ffmpeg(self):
        pidfile = self.busy_bundle(ignore_term=True)
        parent = subprocess.Popen([str(self.executable)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            deadline = time.monotonic() + 3
            while not pidfile.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(pidfile.exists())
            child = int(pidfile.read_text())
            parent.kill()
            parent.wait(timeout=3)
            self.assert_stopped(child)
        finally:
            if parent.poll() is None: parent.kill()
            parent.wait(timeout=3)
            if pidfile.exists():
                try: os.kill(int(pidfile.read_text()), signal.SIGKILL)
                except ProcessLookupError: pass

    def test_cancel_stops_ffmpeg_descendants(self):
        descendant = self.root / "descendant.pid"
        pidfile = self.busy_bundle(ignore_term=True, descendant_file=descendant)
        self.assertEqual(self.run_engine("cancel", str(pidfile)).returncode, 5)
        self.assert_stopped(int(pidfile.read_text()))
        self.assert_stopped(int(descendant.read_text()))

    def test_shutdown_does_not_kill_unrelated_ffmpeg(self):
        self.external.write_text("#!/bin/sh\nwhile :; do :; done\n")
        unrelated = subprocess.Popen([str(self.external)])
        try:
            pidfile = self.busy_bundle()
            self.assertEqual(self.run_engine("shutdown", str(pidfile)).returncode, 5)
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.kill()
            unrelated.wait(timeout=3)

    def test_new_render_can_start_after_cancel_finishes(self):
        pidfile = self.busy_bundle(once=True)
        image = self.root / "input.png"
        image.touch()
        result = self.run_engine("cancel", str(pidfile), str(image))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("NEXT_RUN", result.stdout)
        self.assert_stopped(int(pidfile.read_text()))

    def test_large_stdout_does_not_deadlock(self):
        self.bundled.write_text("#!/bin/sh\ni=0\nwhile [ $i -lt 2048 ]; do printf '%01024d' 0; i=$((i+1)); done\necho BUNDLED_EXECUTED >&2\n")
        self.bundled.chmod(0o755)
        result = self.run_engine()
        self.assertEqual(result.returncode, 0)
        self.assertGreaterEqual(len(result.stdout), 2048 * 1024)
        self.assertIn("BUNDLED_EXECUTED", result.stdout)

    def test_ffmpeg_failure_is_not_reported_as_success(self):
        self.bundled.write_text("#!/bin/sh\nexit 7\n")
        self.bundled.chmod(0o755)
        image = self.root / "input.png"
        image.touch()
        result = self.run_engine("scaler", "lanczos", str(image))
        self.assertEqual(result.returncode, 3, result.stdout)
        self.assertNotIn("Done.", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "macOS architecture selection")
    def test_native_architecture_matches_physical_mac(self):
        shutil.copy2(self.architecture_marker, self.bundled)
        physical_arm = subprocess.run(["/usr/sbin/sysctl", "-n", "hw.optional.arm64"],
                                      capture_output=True, text=True).stdout.strip() == "1"
        result = self.run_engine()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(physical_arm, "Intel Macs are unsupported")
        self.assertIn("NATIVE_ARCH=arm64", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "Intel helper rejection")
    def test_intel_only_ffmpeg_is_rejected(self):
        subprocess.run(["xcrun", "lipo", str(self.architecture_marker), "-thin", "x86_64",
                        "-output", str(self.bundled)], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", str(self.bundled)], check=True,
                       capture_output=True)
        result = self.run_engine()
        self.assertEqual(result.returncode, 99, result.stdout + result.stderr)
        self.assertNotIn("NATIVE_ARCH=x86_64", result.stdout)

    @unittest.skipUnless(sys.platform == "darwin", "Rosetta architecture selection")
    def test_translated_parent_launches_native_arm64(self):
        physical_arm = subprocess.run(["/usr/sbin/sysctl", "-n", "hw.optional.arm64"],
                                      capture_output=True, text=True).stdout.strip() == "1"
        if not physical_arm:
            self.skipTest("requires Apple Silicon")
        available = subprocess.run(["/usr/bin/arch", "-x86_64", "/usr/bin/true"], capture_output=True)
        if available.returncode:
            self.skipTest("Rosetta is not installed")
        shutil.copy2(self.architecture_marker, self.bundled)
        result = subprocess.run(["/usr/bin/arch", "-x86_64", str(self.executable)],
                                capture_output=True, text=True, timeout=8)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("NATIVE_ARCH=arm64", result.stdout)


if __name__ == "__main__":
    unittest.main()
