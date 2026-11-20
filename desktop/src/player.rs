//! The video player in the preview card: plays the imported video (or the finished export) with its sound. A thread
//! owns the decoder and the audio stream; frames are decoded by the engine straight at a display size and sent to
//! the interface with their time. The clock is the audio that has been played, so picture and sound stay together;
//! without an audio track or an output device it is the wall clock.

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use slint::{Rgba8Pixel, SharedPixelBuffer};
use up60p::engine::{Audio, Video};

/// The largest frame played; larger videos are scaled down by the decoder.
const PLAY_SIZE: (u32, u32) = (1280, 720);
/// Decoded sound kept ahead of the output device.
const AUDIO_AHEAD: f64 = 0.4;

pub enum Command {
    Load(PathBuf),
    Play,
    Pause,
    Seek(f64),
}

pub enum Event {
    Frame(SharedPixelBuffer<Rgba8Pixel>, f64),
    Playing(bool),
    Failed(String),
}

/// The size a frame is played at: the video's, reduced to fit `PLAY_SIZE`, with even sides.
pub fn play_size(width: u32, height: u32) -> (u32, u32) {
    let scale = (PLAY_SIZE.0 as f64 / width.max(1) as f64).min(PLAY_SIZE.1 as f64 / height.max(1) as f64).min(1.0);
    let even = |v: f64| ((v.round() as u32) & !1).max(2);
    (even(width as f64 * scale), even(height as f64 * scale))
}

/// Interleaved samples shared with the output device's callback.
struct Shared {
    queue: Mutex<VecDeque<f32>>,
    /// Sample frames the device has played since the last seek.
    played: AtomicU64,
}

/// The sound: the engine's decoder feeding an output stream.
struct Sound {
    stream: cpal::Stream,
    shared: Arc<Shared>,
    rate: u32,
    channels: u32,
    reader: Option<Audio>,
}

fn output_stream<T>(device: &cpal::Device, config: &cpal::StreamConfig, shared: Arc<Shared>) -> Option<cpal::Stream>
where
    T: cpal::SizedSample + cpal::FromSample<f32>,
{
    let channels = config.channels as usize;
    let stream = device.build_output_stream(
        config,
        move |out: &mut [T], _| {
            let mut queue = shared.queue.lock().unwrap_or_else(|e| e.into_inner());
            let available = queue.len().min(out.len()) / channels * channels;
            for (o, s) in out.iter_mut().zip(queue.drain(..available)) {
                *o = T::from_sample(s);
            }
            for o in out[available..].iter_mut() {
                *o = T::from_sample(0.0f32);
            }
            shared.played.fetch_add((available / channels) as u64, Ordering::Relaxed);
        },
        |_| {},
        None,
    );
    stream.ok()
}

impl Sound {
    /// The default output device, or `None` when there is none (a headless machine plays silently).
    fn open() -> Option<Sound> {
        let device = cpal::default_host().default_output_device()?;
        let supported = device.default_output_config().ok()?;
        let config: cpal::StreamConfig = supported.config();
        let shared = Arc::new(Shared { queue: Mutex::new(VecDeque::new()), played: AtomicU64::new(0) });
        let stream = match supported.sample_format() {
            cpal::SampleFormat::F32 => output_stream::<f32>(&device, &config, shared.clone()),
            cpal::SampleFormat::I16 => output_stream::<i16>(&device, &config, shared.clone()),
            cpal::SampleFormat::U16 => output_stream::<u16>(&device, &config, shared.clone()),
            _ => None,
        }?;
        stream.pause().ok()?;
        Some(Sound { stream, shared, rate: config.sample_rate.0, channels: config.channels as u32, reader: None })
    }

    /// Starts the file's sound at `seconds` (reading from the start and dropping what comes before).
    fn start(&mut self, path: &Path, seconds: f64) {
        self.shared.queue.lock().unwrap_or_else(|e| e.into_inner()).clear();
        self.shared.played.store(0, Ordering::Relaxed);
        self.reader = Audio::open(path, self.rate, self.channels).ok();
        let mut skip = (seconds.max(0.0) * self.rate as f64) as u64;
        let mut buf = vec![0f32; 4096 * self.channels as usize];
        while skip > 0 {
            let Some(reader) = self.reader.as_mut() else { return };
            let want = (skip.min(4096) * self.channels as u64) as usize;
            match reader.read(&mut buf[..want]) {
                Ok(n) if n > 0 => skip -= n as u64,
                _ => {
                    self.reader = None;
                    return;
                }
            }
        }
    }

    /// Keeps `AUDIO_AHEAD` seconds decoded ahead of the device.
    fn fill(&mut self) {
        let Some(reader) = self.reader.as_mut() else { return };
        let target = (AUDIO_AHEAD * self.rate as f64) as usize * self.channels as usize;
        let mut buf = vec![0f32; 2048 * self.channels as usize];
        while self.shared.queue.lock().unwrap_or_else(|e| e.into_inner()).len() < target {
            match reader.read(&mut buf) {
                Ok(n) if n > 0 => {
                    let mut queue = self.shared.queue.lock().unwrap_or_else(|e| e.into_inner());
                    queue.extend(&buf[..n * self.channels as usize]);
                }
                _ => {
                    self.reader = None;
                    return;
                }
            }
        }
    }

    fn played(&self) -> f64 {
        self.shared.played.load(Ordering::Relaxed) as f64 / self.rate as f64
    }

    fn has_track(&self) -> bool {
        self.reader.is_some() || !self.shared.queue.lock().unwrap_or_else(|e| e.into_inner()).is_empty()
    }
}

struct Media {
    path: PathBuf,
    video: Video,
    size: (u32, u32),
    frame: Vec<u8>,
}

/// Runs the player until the command sender is dropped, reporting through `send`.
pub fn worker(commands: Receiver<Command>, send: Sender<Event>) {
    let mut sound = Sound::open();
    let mut media: Option<Media> = None;
    // Where playback started (media time) and when (wall clock), while playing.
    let mut started: Option<(f64, Instant)> = None;
    let mut position = 0.0f64;
    let mut next_frame = 0.0f64;

    let clock = |started: &Option<(f64, Instant)>, sound: &Option<Sound>, position: f64| match started {
        Some((from, at)) => match sound.as_ref().filter(|s| s.has_track()) {
            Some(s) => from + s.played(),
            None => from + at.elapsed().as_secs_f64(),
        },
        None => position,
    };
    let show = |media: &mut Media, seconds: f64| -> Result<f64, String> {
        let (w, h) = media.size;
        let shown = media.video.frame_scaled(seconds, w, h, &mut media.frame).map_err(|e| e.to_string())?;
        let buffer = SharedPixelBuffer::clone_from_slice(&media.frame, w, h);
        Ok(if send.send(Event::Frame(buffer, seconds)).is_ok() { shown } else { seconds })
    };

    loop {
        let playing = started.is_some();
        let wait = if playing { Duration::from_millis(4) } else { Duration::from_secs(3600) };
        let command = match commands.recv_timeout(wait) {
            Ok(c) => Some(c),
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => return,
        };
        match command {
            Some(Command::Load(path)) => {
                started = None;
                position = 0.0;
                next_frame = 0.0;
                if let Some(s) = sound.as_mut() {
                    let _ = s.stream.pause();
                    s.reader = None;
                }
                media = match Video::open(&path) {
                    Ok(video) => {
                        let size = play_size(video.width, video.height);
                        let frame = vec![0u8; size.0 as usize * size.1 as usize * 4];
                        Some(Media { path, video, size, frame })
                    }
                    Err(e) => {
                        let _ = send.send(Event::Failed(e.to_string()));
                        None
                    }
                };
                let _ = send.send(Event::Playing(false));
            }
            Some(Command::Play) => {
                let Some(m) = media.as_ref() else { continue };
                if position >= m.video.duration - 0.05 {
                    position = 0.0;
                }
                if let Some(s) = sound.as_mut() {
                    s.start(&m.path, position);
                    s.fill();
                    let _ = s.stream.play();
                }
                started = Some((position, Instant::now()));
                next_frame = position;
                let _ = send.send(Event::Playing(true));
            }
            Some(Command::Pause) => {
                position = clock(&started, &sound, position);
                started = None;
                if let Some(s) = sound.as_mut() {
                    let _ = s.stream.pause();
                }
                let _ = send.send(Event::Playing(false));
            }
            Some(Command::Seek(seconds)) => {
                let Some(m) = media.as_mut() else { continue };
                position = seconds.clamp(0.0, m.video.duration.max(0.0));
                if started.is_some() {
                    if let Some(s) = sound.as_mut() {
                        s.start(&m.path, position);
                        s.fill();
                    }
                    started = Some((position, Instant::now()));
                }
                next_frame = position;
                if let Err(e) = show(m, position) {
                    let _ = send.send(Event::Failed(e));
                }
            }
            None => {}
        }

        // Playing: keep the sound fed and show the frame for the current time when it is due.
        let Some(m) = media.as_mut().filter(|_| started.is_some()) else { continue };
        if let Some(s) = sound.as_mut() {
            s.fill();
        }
        let now = clock(&started, &sound, position);
        if now >= m.video.duration {
            position = m.video.duration;
            started = None;
            if let Some(s) = sound.as_mut() {
                let _ = s.stream.pause();
            }
            let _ = send.send(Event::Playing(false));
            continue;
        }
        if now >= next_frame {
            match show(m, now) {
                Ok(shown) => {
                    // The next frame is due one frame after this one; when decoding falls behind, it is the
                    // frame at the clock's time, so playback skips frames rather than slowing down.
                    let step = if m.video.frame_rate > 0.0 { 1.0 / m.video.frame_rate } else { 1.0 / 30.0 };
                    next_frame = shown + step;
                }
                Err(e) => {
                    let _ = send.send(Event::Failed(e));
                    started = None;
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::mpsc::channel;
    use up60p::engine::{self, Mp4Writer, Quality, WriterConfig};

    /// A 1-second 64x48 clip at 30 fps whose frames get brighter, with a quiet tone.
    fn clip(path: &Path) {
        let config = WriterConfig {
            width: 64,
            height: 48,
            fps_num: 30,
            fps_den: 1,
            quality: Quality::Draft,
            audio_rate: 48_000,
            audio_channels: 2,
        };
        let mut writer = Mp4Writer::create(path, &config).unwrap();
        for n in 0..30u32 {
            writer.add_video(&[(n * 8) as u8, 60, 90, 255].repeat(64 * 48)).unwrap();
            writer.add_audio(&[0.05f32; 1600 * 2], 2).unwrap();
        }
        writer.finish().unwrap();
    }

    #[test]
    fn plays_seeks_and_pauses() {
        if engine::version().is_none() {
            eprintln!("skipped: the MpVFX media engine is not available");
            return;
        }
        let path = std::env::temp_dir().join(format!("myupscaler-player-{}.mp4", std::process::id()));
        clip(&path);
        let (commands, worker_commands) = channel();
        let (worker_events, events) = channel();
        let thread = std::thread::spawn(move || worker(worker_commands, worker_events));
        let next = || events.recv_timeout(Duration::from_secs(10)).expect("the player answers");

        commands.send(Command::Load(path.clone())).unwrap();
        assert!(matches!(next(), Event::Playing(false)));
        commands.send(Command::Seek(0.5)).unwrap();
        match next() {
            Event::Frame(frame, t) => assert_eq!((frame.width(), frame.height(), t), (64, 48, 0.5)),
            _ => panic!("a seek shows the frame"),
        }
        commands.send(Command::Play).unwrap();
        assert!(matches!(next(), Event::Playing(true)));
        // Frames advance until the end, where playback stops by itself.
        let mut last = 0.5;
        loop {
            match next() {
                Event::Frame(_, t) => {
                    assert!(t >= last, "{t} after {last}");
                    last = t;
                }
                Event::Playing(false) => break,
                _ => {}
            }
        }
        assert!(last > 0.8, "played to {last}");
        drop(commands);
        thread.join().unwrap();
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn play_size_fits_and_stays_even() {
        assert_eq!(play_size(1920, 1080), (1280, 720));
        assert_eq!(play_size(3840, 2160), (1280, 720));
        assert_eq!(play_size(1080, 1920), (404, 720));
        assert_eq!(play_size(640, 360), (640, 360));
        assert_eq!(play_size(1, 1), (2, 2));
    }
}
