//! The media engine wrappers' failure paths: every call on bad input returns an error with a message, never a
//! panic, and the writer validates what it is given.

use up60p::engine::{self, Mp4Writer, Quality, WriterConfig};

fn ready() -> bool {
    if engine::version().is_none() {
        eprintln!("skipped: the MpVFX media engine is not available");
        return false;
    }
    true
}

fn scratch(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("up60p-engine-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn config(width: u32, height: u32) -> WriterConfig {
    WriterConfig { width, height, fps_num: 25, fps_den: 1, quality: Quality::Draft, audio_rate: 0, audio_channels: 0 }
}

#[test]
fn bad_inputs_are_errors() {
    if !ready() {
        return;
    }
    let dir = scratch("bad");
    let junk = dir.join("junk.mp4");
    std::fs::write(&junk, b"definitely not a movie").unwrap();
    assert!(engine::probe(&dir.join("absent.mp4")).is_err());
    assert!(engine::Video::open(&junk).is_err());
    assert!(engine::Audio::open(&junk, 48_000, 2).is_err());
    let e = engine::decode_image(b"\x89PNG broken").err().expect("garbage image");
    assert!(!e.message.is_empty());
    assert!(engine::decode_image(&[]).is_err());
}

#[test]
fn writer_validates_sizes_and_frames() {
    if !ready() {
        return;
    }
    let dir = scratch("writer");
    assert!(Mp4Writer::create(&dir.join("odd.mp4"), &config(33, 20)).is_err(), "odd width");
    assert!(Mp4Writer::create(&dir.join("huge.mp4"), &config(engine::MAX_EXPORT_SIDE + 2, 64)).is_err());
    let mut w = Mp4Writer::create(&dir.join("ok.mp4"), &config(32, 16)).unwrap();
    assert!(w.add_video(&[0; 10]).is_err(), "short frame");
    assert!(w.add_audio(&[0.0; 8], 2).is_err(), "no audio track");
    w.add_video(&[128; 32 * 16 * 4]).unwrap();
    w.finish().unwrap();
    let p = engine::probe(&dir.join("ok.mp4")).unwrap();
    assert_eq!(p.video.map(|v| v.codec), Some("h264".into()));
    assert!(p.audio.is_none());
}

#[test]
fn an_unfinished_writer_leaves_nothing() {
    if !ready() {
        return;
    }
    let dir = scratch("dropped");
    let mut w = Mp4Writer::create(&dir.join("half.mp4"), &config(16, 16)).unwrap();
    w.add_video(&[50; 16 * 16 * 4]).unwrap();
    drop(w);
    assert_eq!(std::fs::read_dir(&dir).unwrap().count(), 0);
}

#[test]
fn reader_reports_size_rate_and_rejects_small_buffers() {
    if !ready() {
        return;
    }
    let dir = scratch("reader");
    let path = dir.join("clip.mp4");
    let mut w = Mp4Writer::create(&path, &config(48, 32)).unwrap();
    for n in 0..10u8 {
        w.add_video(&[n * 20; 48 * 32 * 4]).unwrap();
    }
    w.finish().unwrap();
    let mut v = engine::Video::open(&path).unwrap();
    assert_eq!((v.width, v.height, v.is_still), (48, 32, false));
    assert!((v.frame_rate - 25.0).abs() < 0.01);
    assert!((v.duration - 0.4).abs() < 0.05, "{}", v.duration);
    assert!(v.frame_at(0.0, &mut [0; 16]).is_err());
    let mut buf = vec![0; 48 * 32 * 4];
    let shown = v.frame_at(0.22, &mut buf).unwrap();
    assert!((shown - 0.2).abs() < 0.021, "{shown}");
}
