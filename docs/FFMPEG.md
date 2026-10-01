# Bundled FFmpeg provenance

myUpscaler reuses the FFmpeg artifacts pinned in mpvfx commit
`fd4367d52408d772c1ff10f83015a6b2c9c91662`, in
`scripts/third_party/ffmpeg-runtime-manifest.json`.

- Producer: [Shaka Project static-ffmpeg-binaries](https://github.com/shaka-project/static-ffmpeg-binaries)
- Release: [n8.1.2-1](https://github.com/shaka-project/static-ffmpeg-binaries/releases/tag/n8.1.2-1)
- FFmpeg version: 8.1.2
- License: GPL-3.0-or-later
- Minimum macOS version: 15.0

| Asset | SHA-256 before combining/signing |
| --- | --- |
| ffmpeg-osx-arm64 | e7b9fcd97f95f333512d6e8b8ac24d9dbc08f189f36047695499bd7b57214b22 |
| ffmpeg-osx-x64 | 62c87854d851f202fc4a29bdda0fe7b6ebcddd37b863482ce1bdc81151b03fe4 |

`scripts/prepare-bundled-ffmpeg.sh` verifies both downloads before combining
them with `lipo` and ad hoc signing. Xcode embeds the resulting binary at
`Contents/MacOS/ThirdParty/FFmpeg/ffmpeg` and signs it with the app's selected
identity. Runtime resolution uses the running executable's canonical app path,
never a system install or an environment override. A symlink replacing the
binary or its containing directory is rejected.

The helper's sandbox entitlements contain only `app-sandbox` and `inherit`.
It inherits the app's sandbox instead of specifying independent permissions.
CI verifies its signature and launches the packaged helper from a sandboxed
launcher in a copy of the app bundle; it does not launch an inherit-sandbox
executable directly from an unsandboxed shell.

Filter availability is separate from executable provenance. mpvfx's shared build
configuration enables libx264, libx265, libvpx, libsvtav1, libmp3lame, libopus,
Mbed TLS, GPL, and version 3 licensing. It does not enable TensorFlow or OpenVINO.
The shipped app therefore does not offer `sr`, `dnn_processing`, or `zscale`
modes. The preparation script reports these filters for diagnosis, but their
presence alone cannot re-enable unsupported controls. CoreML is a separate
app engine; its controls appear only for model assets included in the bundle.
The native FFmpeg engine accepts only Lanczos. Legacy presets using unavailable
scalers cannot start and must be changed to a supported choice.

For public releases, include FFmpeg's GPL text, build provenance, and matching
corresponding source. mpvfx documents its exact source archives and build-script
revision in
[FFMPEG_SOURCE.md](https://github.com/marshiyar/mpvfx/blob/fd4367d52408d772c1ff10f83015a6b2c9c91662/studio/legal/NOTICES/FFMPEG_SOURCE.md).
Its source archive is `ffmpeg-corresponding-source-n8.1.2-1.tar.gz`, SHA-256
`ba106c32a04effc26c7b585da63c503bf67cbd2a40a7a1b3e0d076693a12add9`.
Make the matching source available alongside any myUpscaler release containing
these binaries. This change prepares a build dependency and CI checks; it does
not create or publish a redistributable app release.
