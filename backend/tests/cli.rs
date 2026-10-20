//! The `up60p` command-line tool: argument handling, header generation and a run on a still.

use std::process::Command;

fn up60p(args: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_up60p")).args(args).output().expect("run up60p")
}

fn scratch(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("up60p-cli-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

#[test]
fn usage_and_bad_arguments() {
    assert!(up60p(&["--help"]).status.success());
    assert_eq!(up60p(&[]).status.code(), Some(2));
    let bad = up60p(&["--set", "no_such_option=1", "x.png"]);
    assert_eq!(bad.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&bad.stderr).contains("unknown option no_such_option"));
    assert_eq!(up60p(&["--set", "no_grain=yes", "x.png"]).status.code(), Some(2));
    assert_eq!(up60p(&["--set", "missing-equals"]).status.code(), Some(2));
}

#[test]
fn writes_the_header() {
    let path = scratch("header").join("include/up60p.h");
    assert!(up60p(&["--write-header", path.to_str().unwrap()]).status.success());
    assert_eq!(std::fs::read_to_string(&path).unwrap(), up60p::header::generate());
}

#[test]
fn processes_a_still_with_options() {
    if up60p::engine::version().is_none() {
        eprintln!("skipped: the MpVFX media engine is not available");
        return;
    }
    let dir = scratch("still");
    let input = dir.join("tile.png");
    up60p::png::write(&input, &[90; 20 * 16 * 4], 20, 16, false).unwrap();
    let out = dir.join("out");
    let run =
        up60p(&["--set", "scale_factor=3", "--set", &format!("outdir={}", out.display()), input.to_str().unwrap()]);
    assert!(run.status.success(), "{}", String::from_utf8_lossy(&run.stderr));
    let png = up60p::engine::decode_image(&std::fs::read(out.join("tile_[restored].png")).unwrap()).unwrap();
    assert_eq!((png.width, png.height), (60, 48));
    assert_eq!(up60p(&[dir.join("absent.png").to_str().unwrap()]).status.code(), Some(1));
}
