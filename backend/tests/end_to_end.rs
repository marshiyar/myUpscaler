//! Whole runs through the engine: a synthetic clip (moving texture, a tone) and a still are made with the engine's
//! own writer and the PNG writer, processed with the app's default settings, and the outputs are probed and
//! decoded. Skipped, with a message, when the engine library is not available to this build.

use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::sync::Mutex;

use up60p::engine::{self, Mp4Writer, Quality, WriterConfig};
use up60p::job::Job;
use up60p::options::{set, Options};

fn engine_ready() -> bool {
    if engine::version().is_none() {
        eprintln!("skipped: the MpVFX media engine is not available (run scripts/prepare-media-engine.sh)");
        return false;
    }
    true
}

fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("up60p-e2e-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// 2 seconds at 24 fps of a textured square moving right over a gradient, with a 440 Hz stereo tone.
fn make_clip(path: &Path, w: u32, h: u32, frames: u32) {
    let cfg = WriterConfig {
        width: w,
        height: h,
        fps_num: 24,
        fps_den: 1,
        quality: Quality::High,
        audio_rate: 48_000,
        audio_channels: 2,
    };
    let mut writer = Mp4Writer::create(path, &cfg).unwrap();
    for n in 0..frames {
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                let inside = x >= 10 + n * 2 && x < 40 + n * 2 && (20..50).contains(&y);
                let v = if inside { 200 - ((x + y) % 7) * 10 } else { 40 + x * 100 / w };
                rgba[i..i + 4].copy_from_slice(&[v as u8, (v / 2) as u8, (255 - v) as u8, 255]);
            }
        }
        writer.add_video(&rgba).unwrap();
        let samples: Vec<f32> = (0..2000)
            .flat_map(|k| {
                let t = (n * 2000 + k) as f32 / 48_000.0;
                let s = (t * 440.0 * std::f32::consts::TAU).sin() * 0.3;
                [s, s]
            })
            .collect();
        writer.add_audio(&samples, 2).unwrap();
    }
    writer.finish().unwrap();
}

/// Runs are process-wide (thread count); keep them one at a time.
static SERIAL: Mutex<()> = Mutex::new(());

fn run(options: &Options, input: &Path) -> Vec<String> {
    let lines = Mutex::new(Vec::new());
    let log = |m: &str| lines.lock().unwrap().push(m.to_owned());
    let cancel = AtomicBool::new(false);
    let job = Job { options, log: &log, cancel: &cancel, dry_run: false };
    let result = job.run(input);
    let lines = lines.into_inner().unwrap();
    if let Err(e) = result {
        panic!("job failed: {e}\n{}", lines.join(""));
    }
    lines
}

#[test]
fn restores_and_upscales_a_video_with_defaults() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_ready() {
        return;
    }
    let dir = scratch("video");
    let input = dir.join("clip.mp4");
    make_clip(&input, 96, 64, 48);

    let mut options = Options::default();
    set(&mut options.outdir, dir.join("out").to_str().unwrap());
    let log = run(&options, &input);
    let text = log.join("");
    assert!(text.contains("Duration: 00:00:02.00"), "{text}");
    assert!(text.contains("frame=") && text.contains("time=") && text.ends_with("Done.\n"), "{text}");

    let output = dir.join("out/clip_[restored].mp4");
    let probe = engine::probe(&output).unwrap();
    let video = probe.video.expect("video stream");
    assert_eq!(video.codec, "h264");
    assert!((video.frame_rate - 60.0).abs() < 0.01, "default interpolates to 60 fps: {}", video.frame_rate);
    let audio = probe.audio.expect("audio is carried over");
    assert_eq!((audio.codec.as_str(), audio.sample_rate, audio.channels), ("flac", 48_000, 2));
    assert!((probe.duration - 2.0).abs() < 0.1, "duration {}", probe.duration);

    let mut reader = engine::Video::open(&output).unwrap();
    assert_eq!((reader.width, reader.height), (192, 128), "2x Lanczos");
    let mut rgba = vec![0u8; 192 * 128 * 4];
    reader.frame_at(1.0, &mut rgba).unwrap();
    // The square sits around x = 2 * (10 + 2 * 24) .. at 1 s: bright and reddish there, darker gradient elsewhere.
    let px = |x: usize, y: usize| &rgba[(y * 192 + x) * 4..(y * 192 + x) * 4 + 3];
    assert!(px(140, 70)[0] > 150, "inside the square: {:?}", px(140, 70));
    assert!(px(20, 110)[0] < 110, "background: {:?}", px(20, 110));
}

#[test]
fn keeps_the_source_rate_without_interpolation_and_cancels_cleanly() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_ready() {
        return;
    }
    let dir = scratch("plain");
    let input = dir.join("clip.mp4");
    make_clip(&input, 64, 48, 24);
    let mut options = Options { no_interpolate: 1, no_denoise: 1, ..Default::default() };
    set(&mut options.scale_factor, "1.5");
    set(&mut options.crf, "28");
    run(&options, &input);
    let output = dir.join("clip_[restored].mp4");
    let probe = engine::probe(&output).unwrap();
    let video = probe.video.unwrap();
    assert!((video.frame_rate - 24.0).abs() < 0.01);
    let reader = engine::Video::open(&output).unwrap();
    assert_eq!((reader.width, reader.height), (96, 72));

    // A cancelled run leaves no output behind.
    let cancelled = dir.join("again");
    std::fs::create_dir_all(&cancelled).unwrap();
    set(&mut options.outdir, cancelled.to_str().unwrap());
    let cancel = AtomicBool::new(true);
    let log = |_: &str| {};
    let job = Job { options: &options, log: &log, cancel: &cancel, dry_run: false };
    assert!(matches!(job.run(&input), Err(up60p::job::JobError::Cancelled)));
    assert_eq!(std::fs::read_dir(&cancelled).unwrap().count(), 0);
}

#[test]
fn restores_a_still_with_transparency() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_ready() {
        return;
    }
    let dir = scratch("still");
    let input = dir.join("logo.png");
    let (w, h) = (40u32, 30u32);
    let mut rgba = Vec::new();
    for y in 0..h {
        for x in 0..w {
            rgba.extend_from_slice(&[(x * 6) as u8, (y * 8) as u8, 128, if x < 20 { 255 } else { 0 }]);
        }
    }
    up60p::png::write(&input, &rgba, w, h, true).unwrap();
    let decoded = engine::decode_image(&std::fs::read(&input).unwrap()).unwrap();
    assert_eq!(decoded.data, rgba, "the PNG writer round-trips through the engine's decoder");

    let options = Options { no_grain: 1, ..Default::default() };
    run(&options, &input);
    let out = engine::decode_image(&std::fs::read(dir.join("logo_[restored].png")).unwrap()).unwrap();
    assert_eq!((out.width, out.height), (80, 60));
    let alpha = |x: u32, y: u32| out.data[((y * 80 + x) * 4 + 3) as usize];
    assert_eq!((alpha(5, 30), alpha(75, 30)), (255, 0));
}

#[test]
fn processes_folders_and_reports_unsupported_files() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_ready() {
        return;
    }
    let dir = scratch("folder");
    std::fs::create_dir_all(dir.join("nested")).unwrap();
    up60p::png::write(&dir.join("a.png"), &[255; 16 * 16 * 4], 16, 16, false).unwrap();
    up60p::png::write(&dir.join("nested/b.png"), &[9; 8 * 8 * 4], 8, 8, false).unwrap();
    std::fs::write(dir.join("notes.txt"), b"ignored").unwrap();
    let options = Options::default();
    run(&options, &dir);
    assert!(dir.join("a_[restored].png").is_file());
    assert!(dir.join("nested/b_[restored].png").is_file());

    std::fs::write(dir.join("broken.mp4"), b"not a video").unwrap();
    let cancel = AtomicBool::new(false);
    let log = |_: &str| {};
    let job = Job { options: &options, log: &log, cancel: &cancel, dry_run: false };
    assert!(job.run(&dir.join("broken.mp4")).is_err());
}

#[test]
fn a_cancel_stops_the_filters_mid_frame() {
    let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    if !engine_ready() {
        return;
    }
    let dir = scratch("cancel");
    let input = dir.join("clip.mp4");
    // Strong non-local means on 720p: one frame takes far longer than the allowance below.
    make_clip(&input, 1280, 720, 4);
    let mut options = Options::default();
    set(&mut options.denoiser, "nlmeans");
    set(&mut options.denoise_strength, "30");
    let cancel = AtomicBool::new(false);
    let log = |_: &str| {};
    let job = Job { options: &options, log: &log, cancel: &cancel, dry_run: false };
    let cancelled_at = std::thread::scope(|s| {
        let run = s.spawn(|| job.run(&input));
        std::thread::sleep(std::time::Duration::from_millis(300));
        cancel.store(true, std::sync::atomic::Ordering::Relaxed);
        let at = std::time::Instant::now();
        assert!(matches!(run.join().unwrap(), Err(up60p::job::JobError::Cancelled)));
        at.elapsed()
    });
    assert!(cancelled_at.as_secs_f64() < 2.0, "cancel took {cancelled_at:?}");
    assert!(!dir.join("clip_[restored].mp4").exists());
}
