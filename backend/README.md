# up60p: myUpscaler's Rust backend

Everything the app does to a video or a still between reading and writing it, in Rust with no third-party crates,
linked into the app as `libup60p.a`. Swift calls it through `up60p.h`, which is generated from the Rust
definitions (`src/header.rs`, written by `up60p --write-header` during the build), so the repository holds no C. Decoding, H.264 encoding
and MP4 muxing go through the MpVFX media engine's C API (`libmpvfx_ffi`, prepared by
`scripts/prepare-media-engine.sh`).

## Pipeline

Frames are held as full-resolution Y'CbCr 4:4:4 float planes (BT.709, 0..255 scale), so filter parameters keep
their usual 8-bit meaning and nothing is rounded until the single dithered conversion back to RGBA8. The chain, in
the app's order (`src/pipeline.rs`):

| Stage | Module | What it does |
| --- | --- | --- |
| decimate | `filters/decimate.rs` | drops frames that repeat the last kept one (8x8 block SAD thresholds) |
| deblock | `filters/deblock.rs` | weak or strong smoothing across the 8x8 block grid where steps are artefacts |
| denoise | `filters/{bm3d,nlmeans,hqdn3d,atadenoise}.rs` | BM3D basic estimate (luma), non-local means, recursive spatio-temporal low-pass, adaptive temporal averaging |
| dering | `filters/hqdn3d.rs` | hqdn3d tuned as a dering pass |
| retime | `filters/interpolate.rs` | constant output rate: motion-compensated (`mci`), blended or repeated frames; refills decimated gaps. With the source timing the app verified, the output has exactly duration × rate frames, interpolation only raises the rate, and the last frame is held |
| scale | `filters/scale.rs` | separable Lanczos-3, even output sides |
| sharpen | `filters/sharpen.rs` | contrast-adaptive sharpening or unsharp mask with threshold |
| deband | `filters/deband.rs` | random-reference deband (blur, or strict for f3kdb and Neo F3kdb) or gradfun |
| second set | same modules | the optional second dering/deblock/denoise/sharpen/deband, each on its own switch |
| eq | `filters/eq.rs` | contrast, brightness, saturation |
| grain | `filters/grain.rs` | temporal uniform grain |

A strength of exactly zero leaves its stage out, as does a neutral EQ. Invalid EQ values, frame rates, Neo F3kdb
parameters and encoder/decoder choices return `UP60P_ERR_INVALID_OPTIONS` before anything is read or written. A
single file that was written returns `UP60P_OK_COMMITTED`; a folder returns `UP60P_OK`. With dry run on, each file
logs one `CMD: ` line with its filter chain instead of being processed.

Videos run as three threads (decode, filter, encode) joined by short queues; filters split rows over all cores
(`src/par.rs`). Audio is decoded and re-encoded as lossless FLAC in the MP4.

## Layout

- `src/lib.rs`: the C API (`up60p_*`), panics stopped at the boundary.
- `src/options.rs`: `up60p_options`, declared once as a field list that produces both the Rust struct and the
  header's struct, and the factory defaults.
- `src/header.rs`: generates `up60p.h` (status codes, options struct, function declarations).
- `src/job.rs`: files, folders, progress lines (`Duration:`, `stage=processing`, `frame= fps= time= speed=`,
  `stage=finalizing`, `Done.`) for the app's parser.
- `src/engine.rs`: the only code that calls the media engine.
- `src/png.rs`: PNG writer (zlib/DEFLATE with fixed Huffman codes and LZ77).
- `src/bin/up60p.rs`: command-line front end; `examples/bench.rs`: per-stage timings.

Without the engine library the crate still builds (`cfg(no_engine)`); the filters and their tests work and the
end-to-end tests report that they were skipped.

## Limits of the engine today

H.264 8-bit 4:2:0 output only (HEVC and 10-bit requests are written as H.264 with a note in the log), at most
7680 pixels per side; audio is written as FLAC. The x265, hardware-acceleration and live-preview settings are kept
in presets but have no effect.
