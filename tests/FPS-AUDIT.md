# FPS and encoder verification

The production C engine previously added `minterpolate` without an explicit
rate for `source`/`lock`. FFmpeg defaults that filter to 60 FPS. It also ignored
numeric FPS settings when interpolation was disabled. Both paths are fixed:
source/lock preserves timestamps with `-fps_mode passthrough`; numeric frame
selection and duplicate mode use `fps` before spatial scaling. Motion and blend
interpolation retain their current position before spatial scaling.

## Run regression tests

```sh
python3 -m unittest discover -s tests -p test_bundled_ffmpeg_engine.py -v
```

The two real FPS tests require local `ffmpeg` and `ffprobe`, otherwise they
explicitly skip. Their three-second 24000/1001 fixture validates 72 source,
90 at 30000/1001, and 36 at 12 FPS, with audio duration within one output frame.
A separate variable-rate fixture validates every relative presentation timestamp.
The other FPS/encoder tests exercise production C command construction with a
small fake bundled executable, without downloading dependencies.

## Recorded experiment

`fps-benchmark-result.json` records a three-second synthetic 320×180 test pattern
at 24000/1001, sine audio, 2× spatial scaling and libx264 ultrafast. The previous
source behavior produced 176 frames at 60 FPS (2.933 seconds), took 0.895 seconds,
and retained 3 seconds of audio. The fixed source path produced 72 frames at
24000/1001 (3.003 seconds), took 0.052 seconds, and retained 3 seconds of audio.
These single synthetic timings isolate unintended interpolation; they are not
an AI benchmark or a general application speed claim.

`videotoolbox-render-result.json` records three one-second real production-engine
renders using a local FFmpeg copied into the test bundle: H.264 8-bit, HEVC 8-bit,
and HEVC 10-bit. All succeeded and ffprobe verified codec/dimensions/pixel depth.
Sandboxed hardware encoding returned VideoToolbox error -12908; the same native
commands succeeded outside the sandbox.

Explicit VideoToolbox selection now reaches the requested hardware encoder.
Its quality parameter is 1–100, not software CRF. The existing 0–51 control maps
monotonically using `100 − value × 99 / 51`; the default 20 maps to 61.18. This
is an explicit control mapping, not a claim of equivalent output quality.
Hardware execution passes `-allow_sw 0`; it cannot silently fall back to a CPU
encoder. CPU presets/CRF flags are omitted for VideoToolbox. H.264 10-bit is
rejected; HEVC 10-bit supplies `p010le` to the encoder.

## Verified CFR endpoint correction

The bridge accepts optional per-file video duration, exact source-rate numerator
and denominator, verified CFR flag, and source frame count. Default zero values
mean unknown. The caller must verify timing from video sample timestamps;
`nominalFrameRate` alone does not establish constant frame rate.

For verified CFR sources, numeric conversion holds the last source image until
`trim=end_frame=N` reaches the finite requested count. `N` is the nearest integer
of video duration × requested FPS, with ties rounded upward and a minimum of one
frame. The clone pad terminates through this downstream trim. This also restores
static tails removed by `mpdecimate`. Motion interpolation remains before scaling.
Equal/lower targets and one-frame sources use frame selection instead of motion
estimation; there are no intermediate motion frames to invent for one image.

`test_fps_endpoints.py` validates one-frame, two-frame, and full clips at 24000/1001
and 30000/1001 with MCI, blend, and duplicate modes: exact output counts, regular
presentation timestamps, and video/audio duration within one output frame. It
also tests a decimated two-second static tail, finite completion, cancellation of
a deliberately long padded target, invalid rational rates, and count overflow.

```sh
python3 -m unittest discover -s tests -p 'test_fps_endpoints.py' -v
```

## Remaining limitations

Unknown or variable-rate timing retains the existing motion interpolation path
and logs that endpoint shortening remains possible. Correcting VFR endpoints
needs reliable per-frame timing and an explicit conversion policy. CFR output
duration is quantized to the requested frame period, so a source duration that
falls between output frames cannot be represented exactly. CoreML target FPS
handling is a separate path. Motion interpolation quality has not been compared
across representative real footage; this change retains its existing settings
and holds only the final available image at the endpoint.

FFmpeg primary references:

- [fps filter](https://ffmpeg.org/ffmpeg-filters.html#fps)
- [minterpolate](https://ffmpeg.org/ffmpeg-filters.html#minterpolate)
- [VideoToolbox encoder source and quality conversion](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/videotoolboxenc.c)
