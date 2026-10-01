"""Production C FPS endpoint/count tests with verified source timing metadata."""
import json
import math
import shutil
import subprocess
import time
import unittest

import test_bundled_ffmpeg_engine as bundled


class FPSEndpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        bundled.BundledFFmpegEngineTests.setUpClass()

    @classmethod
    def tearDownClass(cls):
        bundled.BundledFFmpegEngineTests.tearDownClass()

    def setUp(self):
        self.engine = bundled.BundledFFmpegEngineTests()
        self.engine.setUp()
        self.addCleanup(self.engine.temp.cleanup)

    def capture(self, target, duration="3.003", source_num="24000", source_den="1001", count="72", mode="on"):
        self.engine.bundled.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
        self.engine.bundled.chmod(0o755)
        video = self.engine.root / "input.mp4"
        video.touch()
        return self.engine.run_engine("fps-known", target, mode, str(video), duration, source_num, source_den, count)

    def test_verified_equal_lower_and_single_frame_bypass_motion(self):
        for target, count in (("24000/1001", "72"), ("12", "72"), ("60000/1001", "1")):
            result = self.capture(target, count=count)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("minterpolate=", result.stdout)
            self.assertIn(f"fps=fps={target}", result.stdout)
            self.assertIn("trim=end_frame=", result.stdout)

    def test_verified_motion_padding_is_bounded_by_exact_count(self):
        result = self.capture("60000/1001")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("tpad=stop_mode=clone:stop=-1,minterpolate=fps=60000/1001", result.stdout)
        self.assertIn("trim=end_frame=180,scale=", result.stdout)

    def test_invalid_rational_and_overflow_never_execute(self):
        for target in ("0", "nan", "1/0", "-24", "24,scale=8", "1/2/3", "1/1e999"):
            result = self.capture(target)
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertNotIn("Processing:", result.stdout)
        self.assertEqual(self.capture("60", duration="1e300").returncode, 1)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "requires local FFmpeg/ffprobe")
    def test_native_rational_short_and_full_clips_counts_timestamps_and_audio(self):
        for source_rate, source_count in (("24000/1001", 1), ("24000/1001", 2), ("24000/1001", 24),
                                           ("30000/1001", 1), ("30000/1001", 2), ("30000/1001", 30)):
            for mode in ("on", "blend", "dup"):
                with self.subTest(source=source_rate, count=source_count, mode=mode):
                    self.assert_native_conversion(source_rate, source_count, "60000/1001", mode)

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "requires local FFmpeg/ffprobe")
    def test_native_decimated_static_tail_is_restored_and_terminates(self):
        for mode in ("on", "blend", "dup", "off"):
            self.assert_native_conversion("24000/1001", 48, "60000/1001", mode, static=True)

    def test_source_and_lock_never_pad_even_with_verified_metadata(self):
        for target in ("source", "lock"):
            result = self.capture(target)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertNotIn("tpad=", result.stdout)
            self.assertNotIn("trim=end_frame", result.stdout)

    @unittest.skipUnless(shutil.which("ffmpeg"), "requires local FFmpeg")
    def test_corrupt_input_with_verified_metadata_fails_without_padding_loop(self):
        shutil.copy2(shutil.which("ffmpeg"), self.engine.bundled)
        video = self.engine.root / "input.mp4"
        video.write_bytes(b"not a video")
        start = time.monotonic()
        result = self.engine.run_engine("fps-known", "60", "on", str(video), "3", "24", "1", "72")
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - start, 4)

    @unittest.skipUnless(shutil.which("ffmpeg"), "requires local FFmpeg")
    def test_native_padding_cancel_stops_long_target(self):
        ffmpeg = shutil.which("ffmpeg")
        shutil.copy2(ffmpeg, self.engine.bundled)
        video = self.engine.root / "input.mp4"
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                        "testsrc2=size=160x90:rate=24", "-frames:v", "1", "-c:v", "libx264",
                        "-y", str(video)], check=True, timeout=8)
        output = self.engine.root / "input_[restored].mp4"
        start = time.monotonic()
        result = self.engine.run_engine("fps-known", "60", "on", str(video), "3600", "24", "1", "1",
                                       "no-decimate", "cancel", str(output))
        self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
        self.assertLess(time.monotonic() - start, 4)

    def assert_native_conversion(self, source_rate, source_count, target, mode, static=False):
        ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
        if self.engine.bundled.exists():
            self.engine.bundled.unlink()
        shutil.copy2(ffmpeg, self.engine.bundled)
        numerator, denominator = map(int, source_rate.split("/"))
        duration = source_count * denominator / numerator
        video = self.engine.root / "input.mp4"
        pattern = "color=c=0x806040:" if static else "testsrc2="
        subprocess.run([ffmpeg, "-v", "error", "-f", "lavfi", "-i",
                        f"{pattern}size=160x90:rate={source_rate}:duration={duration:.12f}",
                        "-f", "lavfi", "-i", f"sine=frequency=440:duration={duration:.12f}",
                        "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-y", str(video)],
                       check=True, timeout=8)
        result = self.engine.run_engine("fps-known", target, mode, str(video), str(duration),
                                       str(numerator), str(denominator), str(source_count),
                                       "decimate" if static else "no-decimate")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        output = self.engine.root / "input_[restored].mp4"
        info = json.loads(subprocess.check_output([ffprobe, "-v", "error", "-show_streams", "-of", "json", str(output)]))
        v = next(item for item in info["streams"] if item["codec_type"] == "video")
        audio = next(item for item in info["streams"] if item["codec_type"] == "audio")
        target_num, target_den = map(int, target.split("/"))
        rate = target_num / target_den
        expected = max(1, math.floor(duration * rate + .5 + 1e-9))
        self.assertEqual(int(v["nb_frames"]), expected)
        self.assertEqual(v["avg_frame_rate"], target)
        self.assertLessEqual(abs(float(v["duration"]) - duration), 1 / rate + 1e-5)
        self.assertLessEqual(abs(float(v["duration"]) - float(audio["duration"])), 1 / rate + .001)
        frames = json.loads(subprocess.check_output([ffprobe, "-v", "error", "-select_streams", "v:0", "-show_frames",
                            "-show_entries", "frame=best_effort_timestamp_time", "-of", "json", str(output)]))["frames"]
        pts = [float(frame["best_effort_timestamp_time"]) for frame in frames]
        self.assertAlmostEqual(pts[0], 0, places=5)
        for left, right in zip(pts, pts[1:]):
            self.assertAlmostEqual(right - left, 1 / rate, places=5)
