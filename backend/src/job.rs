//! Processing a file or a folder: decode with the engine, run the filter chain, encode with the engine (videos) or
//! write a PNG (stills). Videos run as three stages on their own threads (decode, filter, encode) connected by short
//! queues, so decoding and encoding overlap the filters.
//!
//! Progress goes to the log as `frame= fps= time= speed=` lines after a `Duration:` line, and a run ends with
//! `Done.`; the app's progress parser reads those.

use std::fmt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{sync_channel, Receiver, SyncSender};
use std::sync::Arc;
use std::time::Instant;

use crate::engine::{self, EngineError, Mp4Writer, WriterConfig};
use crate::frame::Frame;
use crate::options::{text, Options};
use crate::pipeline::{self, Source};
use crate::{par, png};

pub type Log<'a> = &'a (dyn Fn(&str) + Sync);

#[derive(Debug)]
pub enum JobError {
    Cancelled,
    InvalidOptions(String),
    Unsupported(String),
    Io(String),
    Engine(EngineError),
}

impl fmt::Display for JobError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            JobError::Cancelled => write!(f, "cancelled"),
            JobError::InvalidOptions(m) | JobError::Unsupported(m) | JobError::Io(m) => write!(f, "{m}"),
            JobError::Engine(e) => write!(f, "{e}"),
        }
    }
}

impl From<EngineError> for JobError {
    fn from(e: EngineError) -> Self {
        JobError::Engine(e)
    }
}

pub struct Job<'a> {
    pub options: &'a Options,
    pub log: Log<'a>,
    pub cancel: &'a AtomicBool,
    pub dry_run: bool,
}

/// The app's image extensions (`UpscaleRunner`, `EditorState`); anything else is treated as video.
const IMAGE_EXTENSIONS: [&str; 7] = ["png", "jpg", "jpeg", "bmp", "webp", "tif", "tiff"];
const VIDEO_EXTENSIONS: [&str; 5] = ["mp4", "mov", "m4v", "mkv", "webm"];

fn extension(path: &Path) -> String {
    path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default()
}

pub fn is_image(path: &Path) -> bool {
    IMAGE_EXTENSIONS.contains(&extension(path).as_str())
}

/// `HH:MM:SS.cc`.
pub fn timestamp(seconds: f64) -> String {
    let cs = (seconds.max(0.0) * 100.0).round() as u64;
    format!("{:02}:{:02}:{:02}.{:02}", cs / 360_000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
}

impl Job<'_> {
    /// The dry-run plan, one `CMD: ` line per file: input, filter chain and output.
    fn log_command(&self, input: &Path, output: &Path, plan: &pipeline::Plan) {
        let fps = plan.fps.map_or(String::new(), |(n, d)| format!(" -r {n}/{d}"));
        (self.log)(&format!("CMD: up60p -i {} -vf {}{fps} {}\n", input.display(), plan.describe(), output.display()));
    }

    fn cancelled(&self) -> Result<(), JobError> {
        if self.cancel.load(Ordering::Relaxed) {
            Err(JobError::Cancelled)
        } else {
            Ok(())
        }
    }

    /// The restored file's path: `<base>_[restored].mp4` (or `.png`) in the output folder, or beside the input.
    pub fn output_path(&self, input: &Path) -> PathBuf {
        let outdir = text(&self.options.outdir);
        let dir = if outdir.is_empty() {
            input.parent().map(Path::to_path_buf).unwrap_or_default()
        } else {
            PathBuf::from(outdir)
        };
        let base = input.file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_else(|| "output".into());
        dir.join(format!("{base}_[restored].{}", if is_image(input) { "png" } else { "mp4" }))
    }

    pub fn run(&self, input: &Path) -> Result<(), JobError> {
        let meta = std::fs::metadata(input).map_err(|e| JobError::Io(format!("{}: {e}", input.display())))?;
        if meta.is_dir() {
            self.run_directory(input)
        } else {
            self.run_file(input)
        }
    }

    fn run_directory(&self, dir: &Path) -> Result<(), JobError> {
        let mut entries: Vec<PathBuf> = std::fs::read_dir(dir)
            .map_err(|e| JobError::Io(format!("{}: {e}", dir.display())))?
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| !p.file_name().is_some_and(|n| n.to_string_lossy().starts_with('.')))
            .collect();
        entries.sort();
        for path in entries {
            self.cancelled()?;
            if path.is_dir() {
                self.run_directory(&path)?;
            } else if is_image(&path) || VIDEO_EXTENSIONS.contains(&extension(&path).as_str()) {
                self.run_file(&path)?;
            }
        }
        Ok(())
    }

    fn run_file(&self, input: &Path) -> Result<(), JobError> {
        self.cancelled()?;
        let output = self.output_path(input);
        (self.log)(&format!("Processing: {}\n", input.display()));
        if let Some(dir) = output.parent() {
            if !dir.as_os_str().is_empty() {
                std::fs::create_dir_all(dir).map_err(|e| JobError::Io(format!("{}: {e}", dir.display())))?;
            }
        }
        par::set_stopped(false);
        let done = AtomicBool::new(false);
        let result = std::thread::scope(|s| {
            s.spawn(|| watch_cancel(self.cancel, &done));
            let result = if is_image(input) { self.image(input, &output) } else { self.video(input, &output) };
            done.store(true, Ordering::Relaxed);
            result
        });
        par::set_stopped(false);
        if result.is_ok() {
            (self.log)("Done.\n");
        }
        result
    }

    fn image(&self, input: &Path, output: &Path) -> Result<(), JobError> {
        if matches!(extension(input).as_str(), "tif" | "tiff") {
            return Err(JobError::Unsupported(
                "TIFF images are not supported by the Rust engine. Convert the image to PNG first.".into(),
            ));
        }
        let mut plan = pipeline::build(self.options, Source::Image).map_err(JobError::InvalidOptions)?;
        (self.log)(&format!("Filters: {}\n", plan.describe()));
        if self.dry_run {
            self.log_command(input, output, &plan);
            return Ok(());
        }
        let bytes = std::fs::read(input).map_err(|e| JobError::Io(format!("{}: {e}", input.display())))?;
        let image = engine::decode_image(&bytes)?;
        (self.log)(&format!("  Image: {}x{}\n", image.width, image.height));
        let start = Instant::now();
        let frame = Frame::from_rgba(&image.data, image.width as usize, image.height as usize, 0.0, true);
        let mut frames = plan.chain.push(frame);
        frames.extend(plan.chain.flush());
        self.cancelled()?;
        let result = frames.pop().ok_or_else(|| JobError::Io("the filters produced no image".into()))?;
        let rgba = result.to_rgba(0);
        let (w, h) = (result.width() as u32, result.height() as u32);
        png::write(output, &rgba, w, h, result.alpha.is_some())
            .map_err(|e| JobError::Io(format!("{}: {e}", output.display())))?;
        (self.log)(&format!("Output: {} ({w}x{h}) elapsed={:.2}s\n", output.display(), start.elapsed().as_secs_f64()));
        Ok(())
    }

    fn video(&self, input: &Path, output: &Path) -> Result<(), JobError> {
        let probe = engine::probe(input)?;
        let stream =
            probe.video.clone().ok_or_else(|| JobError::Unsupported(format!("{} has no video", input.display())))?;
        if !stream.decodable {
            let reason = stream.reason.unwrap_or_else(|| format!("{} video cannot be decoded", stream.codec));
            return Err(JobError::Unsupported(reason));
        }
        let mut video = engine::Video::open(input)?;
        let src_fps = if video.frame_rate > 0.0 {
            video.frame_rate
        } else if stream.frame_rate > 0.0 {
            stream.frame_rate
        } else {
            30.0
        };
        let duration = if video.duration > 0.0 { video.duration } else { probe.duration };
        (self.log)(&format!(
            "Input #0: {}\n  Duration: {}, {} {}x{}, {:.3} fps\n",
            input.display(),
            timestamp(duration),
            stream.codec,
            video.width,
            video.height,
            src_fps
        ));

        let mut plan =
            pipeline::build(self.options, Source::Video { fps: src_fps }).map_err(JobError::InvalidOptions)?;
        for note in &plan.notes {
            (self.log)(&format!("Note: {note}\n"));
        }
        let (fps_num, fps_den) = plan.fps.unwrap_or((30, 1));
        let out_fps = fps_num as f64 / fps_den as f64;
        let (out_w, out_h) = pipeline::output_size(video.width, video.height, plan.scale);
        if out_w > engine::MAX_EXPORT_SIDE || out_h > engine::MAX_EXPORT_SIDE {
            return Err(JobError::InvalidOptions(format!(
                "The output would be {out_w}x{out_h}; the encoder supports up to {0}x{0}. Lower the scale factor.",
                engine::MAX_EXPORT_SIDE
            )));
        }

        let audio = match &probe.audio {
            Some(a) if a.decodable => {
                let rate = if a.sample_rate == 0 { 48_000 } else { a.sample_rate.clamp(8_000, 192_000) };
                let channels = a.channels.clamp(1, 8);
                match engine::Audio::open(input, rate, channels) {
                    Ok(reader) => Some((reader, rate)),
                    Err(e) => {
                        (self.log)(&format!("Note: the audio track is left out: {e}\n"));
                        None
                    }
                }
            }
            Some(a) => {
                let why = a.reason.clone().unwrap_or_else(|| format!("{} audio cannot be decoded", a.codec));
                (self.log)(&format!("Note: the audio track is left out: {why}\n"));
                None
            }
            None => None,
        };
        let quality = pipeline::quality(&text(&self.options.crf));
        let config = WriterConfig {
            width: out_w,
            height: out_h,
            fps_num,
            fps_den,
            quality,
            audio_rate: audio.as_ref().map_or(0, |a| a.1),
            audio_channels: audio.as_ref().map_or(0, |a| a.0.channels),
        };
        (self.log)(&format!("Filters: {}\n", plan.describe()));
        (self.log)(&format!(
            "Output: {} ({out_w}x{out_h}, {out_fps:.3} fps, H.264 {quality:?}{})\n",
            output.display(),
            audio.as_ref().map_or(String::new(), |(r, rate)| format!(", FLAC {rate} Hz {} ch", r.channels))
        ));
        if self.dry_run {
            self.log_command(input, output, &plan);
            return Ok(());
        }

        let writer = Mp4Writer::create(output, &config)?;
        let started = Instant::now();
        let expected_frames = (duration * out_fps).ceil().max(1.0) as u64;
        let (frame_tx, frame_rx) = sync_channel::<Frame>(3);
        let (out_tx, out_rx) = sync_channel::<Arc<Vec<u8>>>(3);
        let cancel = self.cancel;
        let mut repeat = plan.repeat.take();

        std::thread::scope(|s| {
            let decoder = s.spawn(move || decode(&mut video, src_fps, duration, frame_tx, cancel));
            let encoder = s.spawn(move || encode(writer, audio, out_fps, out_rx, cancel));

            let mut written = 0u64;
            let mut pictures = 0u32;
            let mut last_report = Instant::now();
            // The picture waiting for its repeat count (with frame repetition).
            let mut held: Option<Arc<Vec<u8>>> = None;
            // Sends a finished picture `times` times; false once the encoder has stopped.
            let mut show = |rgba: &Arc<Vec<u8>>, times: u64, written: &mut u64| -> bool {
                for _ in 0..times {
                    if out_tx.send(rgba.clone()).is_err() {
                        return false;
                    }
                    *written += 1;
                    if last_report.elapsed().as_secs_f64() >= 0.5 {
                        last_report = Instant::now();
                        let elapsed = started.elapsed().as_secs_f64().max(1e-3);
                        let time = *written as f64 / out_fps;
                        (self.log)(&format!(
                            "frame={:6} fps={:.2} time={} speed={:.3}x progress={:.1}%\n",
                            written,
                            *written as f64 / elapsed,
                            timestamp(time),
                            time / elapsed,
                            (*written as f64 / expected_frames as f64 * 100.0).min(100.0)
                        ));
                    }
                }
                true
            };
            let mut send = |frames: Vec<Frame>, written: &mut u64| -> bool {
                for f in frames {
                    let rgba = Arc::new(f.to_rgba(pictures));
                    pictures = pictures.wrapping_add(1);
                    let shown = match repeat.as_mut() {
                        Some(r) => {
                            let times = r.push(f.pts);
                            held.replace(rgba).is_none_or(|previous| show(&previous, times, written))
                        }
                        None => show(&rgba, 1, written),
                    };
                    if !shown {
                        return false;
                    }
                }
                true
            };
            (self.log)("stage=processing Decoding, filtering and encoding\n");
            let mut open = true;
            for frame in frame_rx.iter() {
                if cancel.load(Ordering::Relaxed) || !send(plan.chain.push(frame), &mut written) {
                    open = false;
                    break;
                }
            }
            if open && !cancel.load(Ordering::Relaxed) {
                open = send(plan.chain.flush(), &mut written);
            }
            if let (true, Some(r), Some(last)) = (open, repeat.as_mut(), held.take()) {
                show(&last, r.finish(), &mut written);
            }
            drop(out_tx);
            drop(frame_rx);
            if open && !cancel.load(Ordering::Relaxed) {
                (self.log)("stage=finalizing Encoding and writing output\n");
            }
            let decoded = decoder.join().unwrap_or_else(|e| std::panic::resume_unwind(e));
            let encoded = encoder.join().unwrap_or_else(|e| std::panic::resume_unwind(e));
            self.cancelled()?;
            decoded?;
            encoded?;
            let elapsed = started.elapsed().as_secs_f64();
            (self.log)(&format!(
                "frame={:6} fps={:.2} time={} speed={:.3}x progress=100.0%\n",
                written,
                written as f64 / elapsed.max(1e-3),
                timestamp(written as f64 / out_fps),
                duration / elapsed.max(1e-3)
            ));
            let stages: Vec<String> =
                plan.chain.timings().into_iter().map(|(name, secs)| format!("{name} {secs:.2}s")).collect();
            (self.log)(&format!("Stage times: {}\n", stages.join(", ")));
            (self.log)(&format!("Wrote {} ({written} frames) elapsed={elapsed:.2}s\n", output.display()));
            Ok(())
        })
    }
}

/// Tells the filters to stop early once the job is cancelled, until `done`.
fn watch_cancel(cancel: &AtomicBool, done: &AtomicBool) {
    while !done.load(Ordering::Relaxed) {
        if cancel.load(Ordering::Relaxed) {
            par::set_stopped(true);
            return;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
}

/// Samples per average frame interval when reading a video: variable-rate sources have frames shorter than the
/// average, and each must be sampled at least once to be read.
const OVERSAMPLE: f64 = 4.0;

/// Reads every source frame in order, at the display size, and sends it with its presentation time. The reader
/// returns the frame shown at a time, so the stream is sampled more finely than its average rate and repeats are
/// skipped; times past the end return the last frame.
fn decode(
    video: &mut engine::Video,
    fps: f64,
    duration: f64,
    tx: SyncSender<Frame>,
    cancel: &AtomicBool,
) -> Result<(), JobError> {
    let (w, h) = (video.width as usize, video.height as usize);
    let mut rgba = vec![0u8; w * h * 4];
    let step = 1.0 / (fps * OVERSAMPLE);
    let count = (duration / step).ceil().max(1.0) as u64;
    let mut last_shown = f64::NEG_INFINITY;
    for n in 0..count {
        if cancel.load(Ordering::Relaxed) {
            return Err(JobError::Cancelled);
        }
        let shown = video.frame_at((n as f64 + 0.5) * step, &mut rgba)?;
        if shown <= last_shown + 1e-6 {
            continue;
        }
        last_shown = shown;
        let frame = Frame::from_rgba(&rgba, w, h, shown, false);
        if tx.send(frame).is_err() {
            break;
        }
    }
    Ok(())
}

/// Writes frames as they arrive and keeps the audio interleaved with them.
fn encode(
    mut writer: Mp4Writer,
    mut audio: Option<(engine::Audio, u32)>,
    fps: f64,
    rx: Receiver<Arc<Vec<u8>>>,
    cancel: &AtomicBool,
) -> Result<(), JobError> {
    let mut frames = 0u64;
    let mut audio_frames = 0u64;
    let mut buf = vec![0f32; 4096 * 8];
    let mut pump_audio = |writer: &mut Mp4Writer, until: Option<f64>, audio_frames: &mut u64| -> Result<(), JobError> {
        let Some((reader, rate)) = audio.as_mut() else { return Ok(()) };
        let channels = reader.channels;
        loop {
            if until.is_some_and(|t| *audio_frames as f64 / *rate as f64 >= t) {
                return Ok(());
            }
            let want = 4096usize;
            let n = reader.read(&mut buf[..want * channels as usize])?;
            if n == 0 {
                return Ok(());
            }
            writer.add_audio(&buf[..n * channels as usize], channels)?;
            *audio_frames += n as u64;
        }
    };
    for rgba in rx.iter() {
        if cancel.load(Ordering::Relaxed) {
            return Err(JobError::Cancelled);
        }
        writer.add_video(&rgba)?;
        frames += 1;
        pump_audio(&mut writer, Some(frames as f64 / fps), &mut audio_frames)?;
    }
    if cancel.load(Ordering::Relaxed) {
        return Err(JobError::Cancelled);
    }
    if frames == 0 {
        return Err(JobError::Io("no frames were produced".into()));
    }
    pump_audio(&mut writer, None, &mut audio_frames)?;
    writer.finish()?;
    Ok(())
}

pub fn configure_threads(options: &Options) {
    par::set_threads(text(&options.threads).parse::<usize>().unwrap_or(0).min(256));
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::options::set;

    #[test]
    fn output_names() {
        let mut o = Options::default();
        let cancel = AtomicBool::new(false);
        let log = |_: &str| {};
        let job = Job { options: &o, log: &log, cancel: &cancel, dry_run: true };
        assert_eq!(job.output_path(Path::new("/a/b/clip.mov")), PathBuf::from("/a/b/clip_[restored].mp4"));
        assert_eq!(job.output_path(Path::new("/a/b/photo.JPG")), PathBuf::from("/a/b/photo_[restored].png"));
        set(&mut o.outdir, "/out");
        let job = Job { options: &o, log: &log, cancel: &cancel, dry_run: true };
        assert_eq!(job.output_path(Path::new("/a/b/clip.mkv")), PathBuf::from("/out/clip_[restored].mp4"));
    }

    #[test]
    fn timestamps() {
        assert_eq!(timestamp(0.0), "00:00:00.00");
        assert_eq!(timestamp(3725.456), "01:02:05.46");
    }
}
