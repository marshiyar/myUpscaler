//! Writes a short test video (a moving ball over a gradient, with a tone) for screenshots and manual runs:
//! `cargo run --example sample_clip -- out.mp4`. Needs the media engine.

use up60p::engine::{Mp4Writer, Quality, WriterConfig};

fn main() {
    let path = std::env::args().nth(1).expect("usage: sample_clip <out.mp4>");
    let (w, h, fps, frames) = (640u32, 360u32, 24u32, 72u32);
    let config = WriterConfig {
        width: w,
        height: h,
        fps_num: fps,
        fps_den: 1,
        quality: Quality::High,
        audio_rate: 48_000,
        audio_channels: 2,
    };
    let mut writer = Mp4Writer::create(std::path::Path::new(&path), &config).expect("the clip could not be created");
    let samples_per_frame = 48_000 / fps;
    for n in 0..frames {
        let cx = 80.0 + (w as f32 - 160.0) * n as f32 / frames as f32;
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                let d = ((x as f32 - cx).powi(2) + (y as f32 - 180.0).powi(2)).sqrt();
                let c = if d < 48.0 {
                    [250, 196, 80]
                } else {
                    [(30 + x * 60 / w) as u8, (50 + y * 80 / h) as u8, (120 + x * 90 / w) as u8]
                };
                rgba[i..i + 4].copy_from_slice(&[c[0], c[1], c[2], 255]);
            }
        }
        writer.add_video(&rgba).expect("a frame could not be written");
        let tone: Vec<f32> = (0..samples_per_frame)
            .flat_map(|k| {
                let t = (n * samples_per_frame + k) as f32 / 48_000.0;
                let s = (t * 330.0 * std::f32::consts::TAU).sin() * 0.2;
                [s, s]
            })
            .collect();
        writer.add_audio(&tone, 2).expect("audio could not be written");
    }
    writer.finish().expect("the clip could not be finished");
}
