# up60p: myUpscaler's Rust backend

Everything the app does to a video or a still between reading and writing it, in Rust with no third-party crates,
linked into the app as `libup60p.a` behind the C API in `myUpscaler/upscaler/up60p.h`. Decoding, H.264 encoding
and MP4 muxing go through the MpVFX media engine's C API (`libmpvfx_ffi`, prepared by
`scripts/prepare-media-engine.sh`).

## Pipeline

Frames are held as full-resolution Y'CbCr 4:4:4 float planes (BT.709, 0..255 scale), so filter parameters keep
their usual 8-bit meaning and nothing is rounded until the single dithered conversion back to RGBA8. The chain, in
the order the app has always used (`src/pipeline.rs`):

| Stage | Module | What it does |
| --- | --- | --- |
| decimate | `filters/decimate.rs` | drops frames that repeat the last kept one (8x8 block SAD thresholds) |
| deblock | `filters/deblock.rs` | weak or strong smoothing across the 8x8 block grid where steps are artefacts |
| dering | `filters/hqdn3d.rs` | hqdn3d tuned as a dering pass |
| denoise | `filters/{bm3d,nlmeans,hqdn3d,atadenoise}.rs` | BM3D basic estimate (luma), non-local means, recursive spatio-temporal low-pass, adaptive temporal averaging |
| retime | `filters/interpolate.rs` | constant output rate: motion-compensated (`mci`), blended or repeated frames; refills decimated gaps |
| scale | `filters/scale.rs` | separable Lanczos-3, even output sides |
| sharpen | `filters/sharpen.rs` | contrast-adaptive sharpening or unsharp mask with threshold |
| deband | `filters/deband.rs` | random-reference deband (blur or strict) or gradfun |
| second set | same modules | the optional second deblock/dering/denoise/sharpen/deband, with the app's attenuated strengths |
| eq | `filters/eq.rs` | contrast, brightness, saturation |
| grain | `filters/grain.rs` | temporal uniform grain |

Videos run as three threads (decode, filter, encode) joined by short queues; filters split rows over all cores
(`src/par.rs`). Audio is decoded and re-encoded as lossless FLAC in the MP4.

## Layout

- `src/lib.rs`: the C API (`up60p_*`), panics stopped at the boundary.
- `src/options.rs`: `up60p_options` mirrored field for field (`tests/abi.rs` compiles the header and compares
  every offset) and the factory defaults.
- `src/job.rs`: files, folders, progress lines (`Duration:`, `frame= fps= time=`, `Done.`) for the app's parser.
- `src/engine.rs`: the only code that calls the media engine.
- `src/png.rs`: PNG writer (zlib/DEFLATE with fixed Huffman codes and LZ77).
- `src/bin/up60p.rs`: command-line front end; `examples/bench.rs`: per-stage timings.

Without the engine library the crate still builds (`cfg(no_engine)`); the filters and their tests work and the
end-to-end tests report that they were skipped.

## Limits of the engine today

H.264 8-bit 4:2:0 output only (HEVC and 10-bit requests are written as H.264 with a note in the log), at most
7680 pixels per side; audio is written as FLAC. The x265, hardware-acceleration and live-preview settings are kept
in presets but have no effect.
