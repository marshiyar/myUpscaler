//! Safe wrappers over the MpVFX media engine's C API (`mpvfx_media.h`): probing, still-image decode, video frame
//! reading, audio reading and the MP4 writer. This is the only module that talks to the engine.

use std::ffi::{c_char, CStr, CString};
use std::fmt;
use std::path::Path;
use std::ptr::NonNull;

#[repr(C)]
struct RawBuffer {
    data: *mut u8,
    len: usize,
}

#[repr(C)]
#[derive(Default)]
struct RawVideoInfo {
    width: u32,
    height: u32,
    duration: f64,
    frame_rate: f64,
    is_still: u32,
}

#[repr(C)]
struct RawWriterConfig {
    container: u32,
    width: u32,
    height: u32,
    fps_num: u32,
    fps_den: u32,
    quality: u32,
    audio_rate: u32,
    audio_channels: u32,
}

enum VideoReader {}
enum AudioReader {}
enum Writer {}

#[cfg(not(no_engine))]
extern "C" {
    fn mpvfx_version() -> *const c_char;
    fn mpvfx_last_error() -> *const c_char;
    fn mpvfx_buffer_free(buffer: *mut RawBuffer);
    fn mpvfx_probe_json(path: *const c_char) -> *mut c_char;
    fn mpvfx_string_free(s: *mut c_char);
    fn mpvfx_image_decode(data: *const u8, len: usize, out: *mut RawBuffer, width: *mut u32, height: *mut u32) -> i32;
    fn mpvfx_video_open(path: *const c_char) -> *mut VideoReader;
    fn mpvfx_video_close(reader: *mut VideoReader);
    fn mpvfx_video_info(reader: *mut VideoReader, out: *mut RawVideoInfo) -> i32;
    fn mpvfx_video_frame_at(
        reader: *mut VideoReader,
        seconds: f64,
        width: u32,
        height: u32,
        fit: u32,
        out: *mut u8,
        len: usize,
        shown: *mut f64,
    ) -> i32;
    fn mpvfx_audio_open(path: *const c_char, sample_rate: u32, channels: u32) -> *mut AudioReader;
    fn mpvfx_audio_close(reader: *mut AudioReader);
    fn mpvfx_audio_read(reader: *mut AudioReader, out: *mut f32, frames: usize) -> i64;
    fn mpvfx_writer_open(path: *const c_char, config: *const RawWriterConfig) -> *mut Writer;
    fn mpvfx_writer_add_video(writer: *mut Writer, rgba: *const u8, len: usize) -> i32;
    fn mpvfx_writer_add_audio(writer: *mut Writer, samples: *const f32, frames: usize) -> i32;
    fn mpvfx_writer_finish(writer: *mut Writer) -> i32;
    fn mpvfx_writer_close(writer: *mut Writer);
}

/// Stand-ins used when the crate is built without the engine library (`cfg(no_engine)`): every call fails.
#[cfg(no_engine)]
#[allow(clippy::missing_safety_doc)]
mod absent {
    use super::*;
    const UNAVAILABLE: &CStr = c"the MpVFX media engine is not linked into this build";
    pub unsafe fn mpvfx_version() -> *const c_char {
        std::ptr::null()
    }
    pub unsafe fn mpvfx_last_error() -> *const c_char {
        UNAVAILABLE.as_ptr()
    }
    pub unsafe fn mpvfx_buffer_free(_: *mut RawBuffer) {}
    pub unsafe fn mpvfx_probe_json(_: *const c_char) -> *mut c_char {
        std::ptr::null_mut()
    }
    pub unsafe fn mpvfx_string_free(_: *mut c_char) {}
    pub unsafe fn mpvfx_image_decode(_: *const u8, _: usize, _: *mut RawBuffer, _: *mut u32, _: *mut u32) -> i32 {
        -3
    }
    pub unsafe fn mpvfx_video_open(_: *const c_char) -> *mut VideoReader {
        std::ptr::null_mut()
    }
    pub unsafe fn mpvfx_video_close(_: *mut VideoReader) {}
    pub unsafe fn mpvfx_video_info(_: *mut VideoReader, _: *mut RawVideoInfo) -> i32 {
        -3
    }
    #[allow(clippy::too_many_arguments)]
    pub unsafe fn mpvfx_video_frame_at(
        _: *mut VideoReader,
        _: f64,
        _: u32,
        _: u32,
        _: u32,
        _: *mut u8,
        _: usize,
        _: *mut f64,
    ) -> i32 {
        -3
    }
    pub unsafe fn mpvfx_audio_open(_: *const c_char, _: u32, _: u32) -> *mut AudioReader {
        std::ptr::null_mut()
    }
    pub unsafe fn mpvfx_audio_close(_: *mut AudioReader) {}
    pub unsafe fn mpvfx_audio_read(_: *mut AudioReader, _: *mut f32, _: usize) -> i64 {
        -3
    }
    pub unsafe fn mpvfx_writer_open(_: *const c_char, _: *const RawWriterConfig) -> *mut Writer {
        std::ptr::null_mut()
    }
    pub unsafe fn mpvfx_writer_add_video(_: *mut Writer, _: *const u8, _: usize) -> i32 {
        -3
    }
    pub unsafe fn mpvfx_writer_add_audio(_: *mut Writer, _: *const f32, _: usize) -> i32 {
        -3
    }
    pub unsafe fn mpvfx_writer_finish(_: *mut Writer) -> i32 {
        -3
    }
    pub unsafe fn mpvfx_writer_close(_: *mut Writer) {}
}
#[cfg(no_engine)]
use absent::*;

/// An engine failure: the status code and the engine's message for it.
#[derive(Debug, Clone)]
pub struct EngineError {
    pub code: i32,
    pub message: String,
}

impl fmt::Display for EngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{} (engine status {})", self.message, self.code)
    }
}

impl std::error::Error for EngineError {}

pub type Result<T> = std::result::Result<T, EngineError>;

fn last_error(code: i32, fallback: &str) -> EngineError {
    // SAFETY: the engine returns NULL or a NUL-terminated string valid until this thread's next engine call.
    let message = unsafe {
        let p = mpvfx_last_error();
        if p.is_null() {
            String::new()
        } else {
            CStr::from_ptr(p).to_string_lossy().into_owned()
        }
    };
    EngineError { code, message: if message.is_empty() { fallback.to_owned() } else { message } }
}

fn check(code: i32, what: &str) -> Result<()> {
    if code == 0 {
        Ok(())
    } else {
        Err(last_error(code, what))
    }
}

fn c_path(path: &Path) -> Result<CString> {
    CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| EngineError { code: -1, message: format!("path contains a NUL byte: {}", path.display()) })
}

/// The engine's version, or `None` when the library is not linked into this build.
pub fn version() -> Option<String> {
    // SAFETY: a static NUL-terminated string or NULL.
    unsafe {
        let p = mpvfx_version();
        (!p.is_null()).then(|| CStr::from_ptr(p).to_string_lossy().into_owned())
    }
}

/// What the engine reports about a file (the subset of `mpvfx_probe_json` this backend uses).
#[derive(Debug, Clone, Default)]
pub struct Probe {
    pub container: String,
    pub duration: f64,
    pub video: Option<VideoStream>,
    pub audio: Option<AudioStream>,
}

#[derive(Debug, Clone, Default)]
pub struct VideoStream {
    pub codec: String,
    pub frame_rate: f64,
    pub still: bool,
    pub decodable: bool,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct AudioStream {
    pub codec: String,
    pub sample_rate: u32,
    pub channels: u32,
    pub decodable: bool,
    pub reason: Option<String>,
}

pub fn probe(path: &Path) -> Result<Probe> {
    let c = c_path(path)?;
    // SAFETY: c is NUL-terminated; the returned string is freed with mpvfx_string_free.
    let json = unsafe {
        let p = mpvfx_probe_json(c.as_ptr());
        if p.is_null() {
            return Err(last_error(-2, "the file could not be read"));
        }
        let s = CStr::from_ptr(p).to_string_lossy().into_owned();
        mpvfx_string_free(p);
        s
    };
    Ok(parse_probe(&json))
}

/// Reads the engine's probe object. The schema is fixed and flat (`crates/engine/src/probe.rs` in mpvfx-media), so a
/// key lookup inside each stream's object is enough.
pub fn parse_probe(json: &str) -> Probe {
    let video = json::object(json, "video").map(|v| VideoStream {
        codec: json::string(v, "codec").unwrap_or_default(),
        frame_rate: json::number(v, "frameRate").unwrap_or(0.0),
        still: json::boolean(v, "still").unwrap_or(false),
        decodable: json::boolean(v, "decodable").unwrap_or(false),
        reason: json::string(v, "reason"),
    });
    let audio = json::object(json, "audio").map(|a| AudioStream {
        codec: json::string(a, "codec").unwrap_or_default(),
        sample_rate: json::number(a, "sampleRate").unwrap_or(0.0) as u32,
        channels: json::number(a, "channels").unwrap_or(0.0) as u32,
        decodable: json::boolean(a, "decodable").unwrap_or(false),
        reason: json::string(a, "reason"),
    });
    Probe {
        container: json::string(json, "container").unwrap_or_default(),
        duration: json::number(json, "duration").unwrap_or(0.0),
        video,
        audio,
    }
}

/// An RGBA8 image (straight alpha, rows tightly packed).
pub struct Rgba {
    pub width: u32,
    pub height: u32,
    pub data: Vec<u8>,
}

/// Decodes PNG, JPEG, BMP, GIF (first frame), WebP or ICO bytes.
pub fn decode_image(bytes: &[u8]) -> Result<Rgba> {
    let mut buf = RawBuffer { data: std::ptr::null_mut(), len: 0 };
    let (mut width, mut height) = (0u32, 0u32);
    // SAFETY: bytes is valid for its length; buf is filled by the engine and released below.
    let code = unsafe { mpvfx_image_decode(bytes.as_ptr(), bytes.len(), &mut buf, &mut width, &mut height) };
    check(code, "the image could not be decoded")?;
    // SAFETY: on success buf.data holds buf.len bytes owned by the engine.
    let data = unsafe {
        let v = if buf.data.is_null() { Vec::new() } else { std::slice::from_raw_parts(buf.data, buf.len).to_vec() };
        mpvfx_buffer_free(&mut buf);
        v
    };
    if data.len() != width as usize * height as usize * 4 {
        return Err(EngineError { code: -2, message: "the decoded image has an unexpected size".into() });
    }
    Ok(Rgba { width, height, data })
}

/// The engine's video reader. A handle is used by one thread at a time, which `&mut self` enforces.
pub struct Video {
    raw: NonNull<VideoReader>,
    pub width: u32,
    pub height: u32,
    pub duration: f64,
    pub frame_rate: f64,
    pub is_still: bool,
}

// SAFETY: the engine allows a handle to be used from any thread, one thread at a time; `Video` is not `Sync`.
unsafe impl Send for Video {}

impl Video {
    pub fn open(path: &Path) -> Result<Video> {
        let c = c_path(path)?;
        // SAFETY: c is NUL-terminated.
        let raw = NonNull::new(unsafe { mpvfx_video_open(c.as_ptr()) })
            .ok_or_else(|| last_error(-2, "the video could not be opened"))?;
        let mut info = RawVideoInfo::default();
        // SAFETY: raw is a live handle; it is closed by Drop, including on the error path below.
        let mut video = Video { raw, width: 0, height: 0, duration: 0.0, frame_rate: 0.0, is_still: false };
        check(unsafe { mpvfx_video_info(video.raw.as_ptr(), &mut info) }, "the video could not be read")?;
        video.width = info.width;
        video.height = info.height;
        video.duration = info.duration;
        video.frame_rate = info.frame_rate;
        video.is_still = info.is_still != 0;
        Ok(video)
    }

    /// The frame shown at `seconds`, at the display size, into `out` (width * height * 4 bytes). Returns the
    /// presentation time of the frame returned.
    pub fn frame_at(&mut self, seconds: f64, out: &mut [u8]) -> Result<f64> {
        let needed = self.width as usize * self.height as usize * 4;
        if out.len() < needed {
            return Err(EngineError { code: -1, message: "frame buffer too small".into() });
        }
        let mut shown = 0.0f64;
        // SAFETY: out holds at least width * height * 4 bytes; fit 1 = stretch to the (native) size.
        let code = unsafe {
            mpvfx_video_frame_at(
                self.raw.as_ptr(),
                seconds,
                self.width,
                self.height,
                1,
                out.as_mut_ptr(),
                needed,
                &mut shown,
            )
        };
        check(code, "a video frame could not be decoded")?;
        Ok(shown)
    }
}

impl Drop for Video {
    fn drop(&mut self) {
        // SAFETY: raw came from mpvfx_video_open and is closed once.
        unsafe { mpvfx_video_close(self.raw.as_ptr()) }
    }
}

/// The engine's audio reader: the first audio track as interleaved float samples.
pub struct Audio {
    raw: NonNull<AudioReader>,
    pub channels: u32,
}

// SAFETY: as for `Video`.
unsafe impl Send for Audio {}

impl Audio {
    pub fn open(path: &Path, sample_rate: u32, channels: u32) -> Result<Audio> {
        let c = c_path(path)?;
        // SAFETY: c is NUL-terminated.
        let raw = NonNull::new(unsafe { mpvfx_audio_open(c.as_ptr(), sample_rate, channels) })
            .ok_or_else(|| last_error(-2, "the audio could not be opened"))?;
        Ok(Audio { raw, channels })
    }

    /// Fills `out` with up to `out.len() / channels` frames; returns the frames read (0 at the end).
    pub fn read(&mut self, out: &mut [f32]) -> Result<usize> {
        let frames = out.len() / self.channels.max(1) as usize;
        // SAFETY: out holds frames * channels floats.
        let n = unsafe { mpvfx_audio_read(self.raw.as_ptr(), out.as_mut_ptr(), frames) };
        if n < 0 {
            return Err(last_error(n as i32, "the audio could not be decoded"));
        }
        Ok(n as usize)
    }
}

impl Drop for Audio {
    fn drop(&mut self) {
        // SAFETY: raw came from mpvfx_audio_open and is closed once.
        unsafe { mpvfx_audio_close(self.raw.as_ptr()) }
    }
}

/// H.264 quality tiers of the engine's encoder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Quality {
    Draft = 0,
    Standard = 1,
    High = 2,
}

/// Largest export side the engine's writer accepts.
pub const MAX_EXPORT_SIDE: u32 = 7680;

#[derive(Debug, Clone, Copy)]
pub struct WriterConfig {
    pub width: u32,
    pub height: u32,
    pub fps_num: u32,
    pub fps_den: u32,
    pub quality: Quality,
    /// 0 for no audio track.
    pub audio_rate: u32,
    pub audio_channels: u32,
}

/// The engine's MP4 writer (H.264 video, FLAC audio). It writes `path.partial` and renames it on `finish`; dropping
/// an unfinished writer deletes the partial file.
pub struct Mp4Writer {
    raw: NonNull<Writer>,
    frame_bytes: usize,
}

// SAFETY: as for `Video`.
unsafe impl Send for Mp4Writer {}

impl Mp4Writer {
    pub fn create(path: &Path, cfg: &WriterConfig) -> Result<Mp4Writer> {
        let c = c_path(path)?;
        let raw_cfg = RawWriterConfig {
            container: 0,
            width: cfg.width,
            height: cfg.height,
            fps_num: cfg.fps_num,
            fps_den: cfg.fps_den,
            quality: cfg.quality as u32,
            audio_rate: cfg.audio_rate,
            audio_channels: cfg.audio_channels,
        };
        // SAFETY: c is NUL-terminated and raw_cfg outlives the call.
        let raw = NonNull::new(unsafe { mpvfx_writer_open(c.as_ptr(), &raw_cfg) })
            .ok_or_else(|| last_error(-1, "the output file could not be created"))?;
        Ok(Mp4Writer { raw, frame_bytes: cfg.width as usize * cfg.height as usize * 4 })
    }

    pub fn add_video(&mut self, rgba: &[u8]) -> Result<()> {
        if rgba.len() != self.frame_bytes {
            return Err(EngineError { code: -1, message: "frame has the wrong size".into() });
        }
        // SAFETY: rgba holds exactly one frame.
        check(unsafe { mpvfx_writer_add_video(self.raw.as_ptr(), rgba.as_ptr(), rgba.len()) }, "encoding failed")
    }

    pub fn add_audio(&mut self, samples: &[f32], channels: u32) -> Result<()> {
        let frames = samples.len() / channels.max(1) as usize;
        // SAFETY: samples holds frames * channels floats.
        check(unsafe { mpvfx_writer_add_audio(self.raw.as_ptr(), samples.as_ptr(), frames) }, "audio encoding failed")
    }

    pub fn finish(self) -> Result<()> {
        // SAFETY: the handle stays valid after finish and is closed by Drop.
        check(unsafe { mpvfx_writer_finish(self.raw.as_ptr()) }, "the output file could not be finished")
    }
}

impl Drop for Mp4Writer {
    fn drop(&mut self) {
        // SAFETY: raw came from mpvfx_writer_open and is closed once.
        unsafe { mpvfx_writer_close(self.raw.as_ptr()) }
    }
}

/// Just enough JSON reading for the engine's probe output: values looked up by key inside a flat object.
mod json {
    /// The text of the object value of `key` (`None` when absent or `null`).
    pub fn object<'a>(json: &'a str, key: &str) -> Option<&'a str> {
        let start = value_start(json, key)?;
        let rest = &json[start..];
        if !rest.starts_with('{') {
            return None;
        }
        let (mut depth, mut in_str, mut escaped) = (0usize, false, false);
        for (i, ch) in rest.char_indices() {
            if in_str {
                match ch {
                    _ if escaped => escaped = false,
                    '\\' => escaped = true,
                    '"' => in_str = false,
                    _ => {}
                }
                continue;
            }
            match ch {
                '"' => in_str = true,
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if depth == 0 {
                        return Some(&rest[..=i]);
                    }
                }
                _ => {}
            }
        }
        None
    }

    pub fn number(json: &str, key: &str) -> Option<f64> {
        let rest = &json[value_start(json, key)?..];
        let end = rest.find(|c: char| !(c.is_ascii_digit() || "+-.eE".contains(c))).unwrap_or(rest.len());
        rest[..end].parse().ok()
    }

    pub fn boolean(json: &str, key: &str) -> Option<bool> {
        let rest = &json[value_start(json, key)?..];
        if rest.starts_with("true") {
            Some(true)
        } else if rest.starts_with("false") {
            Some(false)
        } else {
            None
        }
    }

    pub fn string(json: &str, key: &str) -> Option<String> {
        let rest = json[value_start(json, key)?..].strip_prefix('"')?;
        let mut out = String::new();
        let mut chars = rest.chars();
        while let Some(ch) = chars.next() {
            match ch {
                '"' => return Some(out),
                '\\' => match chars.next()? {
                    'n' => out.push('\n'),
                    't' => out.push('\t'),
                    'u' => {
                        let hex: String = chars.by_ref().take(4).collect();
                        out.push(u32::from_str_radix(&hex, 16).ok().and_then(char::from_u32).unwrap_or('\u{fffd}'));
                    }
                    other => out.push(other),
                },
                _ => out.push(ch),
            }
        }
        None
    }

    /// Byte offset of the value of the first `"key":` at the top level of `json`.
    fn value_start(json: &str, key: &str) -> Option<usize> {
        let needle = format!("\"{key}\"");
        let bytes = json.as_bytes();
        let (mut depth, mut in_str, mut escaped) = (0usize, false, false);
        let mut i = 0;
        while i < bytes.len() {
            let b = bytes[i];
            if in_str {
                match b {
                    _ if escaped => escaped = false,
                    b'\\' => escaped = true,
                    b'"' => in_str = false,
                    _ => {}
                }
                i += 1;
                continue;
            }
            match b {
                b'{' | b'[' => depth += 1,
                b'}' | b']' => depth = depth.saturating_sub(1),
                b'"' if depth == 1 && json[i..].starts_with(&needle) => {
                    let after = json[i + needle.len()..].trim_start();
                    if let Some(v) = after.strip_prefix(':') {
                        let v = v.trim_start();
                        return Some(json.len() - v.len());
                    }
                    in_str = true;
                }
                b'"' => in_str = true,
                _ => {}
            }
            i += 1;
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_engine_probe_json() {
        let json = r#"{"container":"mp4","duration":2.5,"video":{"codec":"h264","width":64,"height":48,"sarNum":1,
            "sarDen":1,"rotation":0,"orientation":1,"displayWidth":64,"displayHeight":48,"frameRate":29.97,
            "frames":75,"still":false,"hdr":false,"decodable":true},"audio":{"codec":"aac","sampleRate":44100,
            "channels":2,"decodable":false,"reason":"No \"AAC\" here"}}"#;
        let p = parse_probe(json);
        assert_eq!(p.container, "mp4");
        assert_eq!(p.duration, 2.5);
        let v = p.video.unwrap();
        assert_eq!((v.codec.as_str(), v.frame_rate, v.still, v.decodable), ("h264", 29.97, false, true));
        let a = p.audio.unwrap();
        assert_eq!((a.sample_rate, a.channels, a.decodable), (44100, 2, false));
        assert_eq!(a.reason.as_deref(), Some("No \"AAC\" here"));
    }

    #[test]
    fn null_streams_are_absent() {
        let p = parse_probe(r#"{"container":"png","duration":0,"video":null,"audio":null}"#);
        assert!(p.video.is_none() && p.audio.is_none());
    }
}
