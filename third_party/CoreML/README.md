# Included Core ML models

Real-ESRGAN x4 and x8, converted to Core ML by Arshiya (Marshiyar).
The upstream Real-ESRGAN BSD 3-Clause notice is retained in [LICENSE.txt](LICENSE.txt).

The app uses RGB NCHW tensors: x4 accepts `[1, 3, 256, 256]` and returns
`[1, 3, 1024, 1024]`; x8 accepts `[1, 3, 64, 64]` and returns `[1, 3, 512, 512]`.
Both models passed native Core ML loading. The x8 model also passed a bounded
CPU prediction with finite, nonconstant output. These checks do not establish
quality on representative footage or application export performance.

The bundles record Core ML Tools 9.0, PyTorch 2.9.1 and conversion date
2025-12-09. File checksums in `manifest.json` identify the included artifacts.
