//! Times the backend on a synthetic noisy 720p clip made with the engine's writer:
//! `cargo run --release --example bench [frames]`. Prints each configuration's stage times and throughput.

use std::sync::atomic::AtomicBool;

use up60p::engine::{Mp4Writer, Quality, WriterConfig};
use up60p::options::{set, Options};

fn main() {
    let frames: u32 = std::env::args().nth(1).and_then(|a| a.parse().ok()).unwrap_or(48);
    let (w, h) = (1280u32, 720u32);
    let dir = std::env::temp_dir().join("up60p-bench");
    std::fs::create_dir_all(&dir).expect("temp dir");
    let input = dir.join("bench.mp4");
    let cfg = WriterConfig {
        width: w,
        height: h,
        fps_num: 24,
        fps_den: 1,
        quality: Quality::Standard,
        audio_rate: 0,
        audio_channels: 0,
    };
    let mut writer = Mp4Writer::create(&input, &cfg).expect("writer");
    for n in 0..frames {
        let mut rgba = vec![0u8; (w * h * 4) as usize];
        for y in 0..h {
            for x in 0..w {
                let i = ((y * w + x) * 4) as usize;
                let noise = up60p::frame::hash3(x, y, n) % 24;
                let checker = if ((x + n * 4) / 64 + y / 64) % 2 == 0 { 30 } else { 0 };
                let v = ((x + n * 4) * 255 / (w + 200) + checker + noise).min(255) as u8;
                rgba[i..i + 4].copy_from_slice(&[v, v / 2 + 40, 255 - v, 255]);
            }
        }
        writer.add_video(&rgba).expect("frame");
    }
    writer.finish().expect("finish");

    type Tweak = fn(&mut Options);
    let configs: [(&str, Tweak); 3] = [
        ("defaults: bm3d, mci to 60 fps, x2", |_| {}),
        ("hqdn3d, no interpolation, x2", |o| {
            set(&mut o.denoiser, "hqdn3d");
            o.no_interpolate = 1;
        }),
        ("no filters, x2", |o| {
            for f in [&mut o.no_deblock, &mut o.no_denoise, &mut o.no_interpolate, &mut o.no_sharpen] {
                *f = 1;
            }
            for f in [&mut o.no_deband, &mut o.no_eq, &mut o.no_grain, &mut o.no_decimate] {
                *f = 1;
            }
        }),
    ];
    for (label, tweak) in configs {
        let mut o = Options::default();
        set(&mut o.outdir, dir.join("out").to_str().unwrap_or("."));
        tweak(&mut o);
        let cancel = AtomicBool::new(false);
        let log = |m: &str| {
            if m.starts_with("Stage times") || m.starts_with("Wrote") {
                eprint!("  {m}");
            }
        };
        let t = std::time::Instant::now();
        let job = up60p::job::Job { options: &o, log: &log, cancel: &cancel, dry_run: false };
        job.run(&input).expect("run");
        let secs = t.elapsed().as_secs_f64();
        eprintln!(
            "{label}: {secs:.2}s, {:.2} source frames/s on {} threads",
            frames as f64 / secs,
            up60p::par::threads()
        );
    }
}
