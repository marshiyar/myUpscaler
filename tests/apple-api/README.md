# Native video I/O regression

Run `tests/apple-api/run.sh` from the repository on an Apple Silicon Mac with Xcode installed. It compiles against a macOS 15.2 deployment target and creates/deletes only temporary synthetic H.264 clips. No ML models, downloads or external tools are required.

The test exercises both the legacy AVAssetReader/AVAssetWriter adaptor path and, on macOS 26+, the asynchronous provider/receiver path. It checks 30 decoded frames, exact presentation timestamps, dimensions, BGRA channel order, cancelled readers/writers, and task cancellation. This is a correctness test, not an end-to-end AI benchmark. The printed total time includes setup and codec warmup; the legacy path runs first, so the two numbers cannot establish a speedup.

Validated on macOS 27.2 (26B5086k), Xcode 27.0 (27A266a). Both paths passed. The restricted execution sandbox returned AVFoundation error -11834 (encoder unavailable); running the same test outside that sandbox passed. macOS 15.2 was typechecked but is not available for runtime testing here.

The modern APIs are available from macOS 26. The installed macOS 27 SDK deprecates older reader/writer attachment and start methods; availability guards keep the legacy path usable on macOS 15.2. The adapter retains decoder buffers without copying (`alwaysCopiesSampleData = false`) and recycles encoder pixel buffers from a pool. These optimizations do not remove the engine's CPU tensor conversion, model prediction transfers, or tile blending.

An append attempted after cancelling a modern writer can suspend rather than fail. The adapter rejects appends unless the writer is still writing. Callers must also cancel their processing task to interrupt an append already awaiting backpressure; a custom polling cancellation flag alone cannot wake a suspended receiver.

Primary references:

- [Apple: AVAssetReader outputProvider(for:)](https://developer.apple.com/documentation/avfoundation/avassetreader/outputprovider(for:))
- [Apple: AVAssetReaderOutput.Provider](https://developer.apple.com/documentation/avfoundation/avassetreaderoutput/provider)
- [Apple: AVAssetWriterInput.PixelBufferReceiver](https://developer.apple.com/documentation/avfoundation/avassetwriterinput/pixelbufferreceiver)
- [Apple: MLModel](https://developer.apple.com/documentation/coreml/mlmodel)
- [Apple: Accelerate ARGB8888 to planar Float conversion](https://developer.apple.com/documentation/accelerate/vimageconvert_argb8888toplanarf(_:_:_:_:_:_:_:_:))

Further candidates need model-specific measurement before implementation: reuse tensor/tile buffers; benchmark Accelerate deinterleaving with correct BGRA channel permutation; evaluate image-input CoreML models only if their input contract and color normalization match; use Metal preprocessing only when it avoids, rather than adds, CPU/GPU synchronization. `.all` compute units and asynchronous CoreML prediction are already used. No FFmpeg replacement or model precision/quality change is justified by this I/O test.
