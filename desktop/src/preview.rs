//! The preview: one frame of the input at a chosen time, as decoded or through the export's filter chain. It runs on
//! its own thread and only the latest request is served, so dragging the position or a slider stays responsive.
//! Like the macOS app's preview it approximates the export: the frame is reduced to at most `PREVIEW_WIDTH` pixels
//! wide before filtering, and temporal stages (decimation, retiming) are left out.

use std::path::{Path, PathBuf};
use std::sync::mpsc::{Receiver, Sender};

use slint::{Rgba8Pixel, SharedPixelBuffer};
use up60p::engine::{self, Video};
use up60p::filters::scale::Lanczos;
use up60p::filters::Chain;
use up60p::frame::Frame;
use up60p::options::Options;
use up60p::pipeline::{self, Source};

/// Widest frame the filtered preview processes; wider sources are reduced first.
pub const PREVIEW_WIDTH: usize = 960;

pub struct Request {
    pub path: PathBuf,
    pub seconds: f64,
    /// The export settings to preview, or `None` for the decoded frame.
    pub filters: Option<Box<Options>>,
}

pub enum Reply {
    Frame(SharedPixelBuffer<Rgba8Pixel>),
    Failed(String),
}

fn to_buffer(rgba: &[u8], w: usize, h: usize) -> SharedPixelBuffer<Rgba8Pixel> {
    SharedPixelBuffer::clone_from_slice(rgba, w as u32, h as u32)
}

/// Runs the export's spatial filters on a decoded RGBA frame.
pub fn filtered(rgba: &[u8], w: usize, h: usize, options: &Options) -> Result<(Vec<u8>, usize, usize), String> {
    let mut frame = Frame::from_rgba(rgba, w, h, 0.0, true);
    if w > PREVIEW_WIDTH {
        let mut reduce = Chain::default();
        reduce.push_stage(Box::new(Lanczos { factor: PREVIEW_WIDTH as f64 / w as f64 }));
        frame = reduce.push(frame).pop().ok_or("the preview could not be reduced")?;
    }
    let mut plan = pipeline::build(options, Source::Image)?;
    let mut out = plan.chain.push(frame);
    out.extend(plan.chain.flush());
    let result = out.pop().ok_or("the filters produced no frame")?;
    Ok((result.to_rgba(0), result.width(), result.height()))
}

struct Open {
    path: PathBuf,
    video: Video,
}

fn open(cache: &mut Option<Open>, path: &Path) -> Result<(), String> {
    if cache.as_ref().is_some_and(|c| c.path == path) {
        return Ok(());
    }
    *cache = None;
    let video = Video::open(path).map_err(|e| e.to_string())?;
    *cache = Some(Open { path: path.to_owned(), video });
    Ok(())
}

fn serve(cache: &mut Option<Open>, request: &Request) -> Result<SharedPixelBuffer<Rgba8Pixel>, String> {
    open(cache, &request.path)?;
    let video = &mut cache.as_mut().expect("opened above").video;
    let (w, h) = (video.width as usize, video.height as usize);
    let mut rgba = vec![0u8; w * h * 4];
    video.frame_at(request.seconds.max(0.0), &mut rgba).map_err(|e| e.to_string())?;
    match &request.filters {
        None => Ok(to_buffer(&rgba, w, h)),
        Some(options) => {
            let (out, ow, oh) = filtered(&rgba, w, h, options)?;
            Ok(to_buffer(&out, ow, oh))
        }
    }
}

/// Serves requests until the sender is dropped, answering only the newest one queued.
pub fn worker(requests: Receiver<Request>, replies: Sender<Reply>, wake: impl Fn() + Send) {
    let mut cache = None;
    while let Ok(mut request) = requests.recv() {
        while let Ok(newer) = requests.try_recv() {
            request = newer;
        }
        if engine::version().is_none() {
            let _ = replies.send(Reply::Failed("The MpVFX media engine is missing; no preview.".into()));
        } else {
            let reply = match serve(&mut cache, &request) {
                Ok(frame) => Reply::Frame(frame),
                Err(e) => Reply::Failed(e),
            };
            if replies.send(reply).is_err() {
                return;
            }
        }
        wake();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn filtered_preview_is_reduced_and_scaled() {
        let (w, h) = (1280usize, 720usize);
        let rgba: Vec<u8> = (0..w * h).flat_map(|i| [(i % 251) as u8, (i % 127) as u8, 90, 255]).collect();
        let o = Options { no_denoise: 1, ..Default::default() }; // keep the test quick
        let (out, ow, oh) = filtered(&rgba, w, h, &o).unwrap();
        assert_eq!((ow, oh), (PREVIEW_WIDTH * 2, 540 * 2));
        assert_eq!(out.len(), ow * oh * 4);
    }

    #[test]
    fn invalid_settings_are_reported() {
        let rgba = vec![128u8; 16 * 16 * 4];
        let mut o = Options { no_eq: 0, ..Default::default() };
        up60p::options::set(&mut o.eq_saturation, "9");
        assert!(filtered(&rgba, 16, 16, &o).unwrap_err().contains("EQ"));
    }
}
