# CoreML AI Upscaler Integration

This document explains how to use the CoreML-based AI upscaler in myUpscaler.

## Overview

The CoreML engine provides GPU-accelerated AI upscaling using Real-ESRGAN models, fully compatible with Apple's App Store requirements (no external binaries needed).

## Features

- **4x Upscaling**: Uses Real-ESRGAN x4 models for high-quality upscaling
- **GPU Acceleration**: Automatically uses Neural Engine / GPU via CoreML
- **App Store Compliant**: Uses only Apple frameworks (CoreML, Vision, AVFoundation)
- **Automatic Model Management**: Downloads and compiles models on first use

## Setup (For Developers)

### 1. Obtain a CoreML Model

You need a Real-ESRGAN model converted to CoreML format (`.mlmodel`). 

**Option A: Convert Existing Model**
- Use `coremltools` to convert PyTorch/ONNX models to CoreML
- Example conversion script:
```python
import coremltools as ct
import torch

# Load your PyTorch model
model = torch.load('RRDB_ESRGAN_x4.pth')
model.eval()

# Convert to CoreML
mlmodel = ct.convert(model, 
                     inputs=[ct.TensorType(name="input", shape=(1, 3, 256, 256))],
                     compute_units=ct.ComputeUnit.ALL)

# Save
mlmodel.save("RealESRGAN_x4.mlmodel")
```

**Option B: Use Pre-converted Model**
- Download a pre-converted `.mlmodel` file from a trusted source
- Ensure it's compatible with Real-ESRGAN x4 architecture

### 2. Add Model to Xcode Project

1. **Add the model file to your Xcode project:**
   - Drag `RealESRGAN_x4.mlmodel` into your Xcode project
   - Ensure it's added to the `myUpscaler` target
   - Place it in the `myUpscaler` folder (or create a `Models` subfolder)

2. **Verify it's included in the bundle:**
   - Select the file in Xcode
   - In File Inspector, ensure "Target Membership" includes `myUpscaler`
   - The file should appear in "Copy Bundle Resources" build phase

3. **Build and test:**
   - The app will automatically find the model in the bundle
   - On first use, it will compile to `.mlmodelc` format
   - Compiled model is cached in `~/Library/Application Support/myUpscaler/Models/`

### 3. User Experience

**For end users:** No setup required! The model is bundled with the app.

1. Open Settings
2. Set **Scaler** to `coreml`
3. Process your video/image as normal

The first run may take longer (model compilation), but subsequent runs will be faster.

## Technical Details

### Model Requirements

- **Input**: RGB image (any size, will be processed in tiles if needed)
- **Output**: 4x upscaled RGB image
- **Format**: CoreML `.mlmodel` (will be compiled to `.mlmodelc`)

### Processing Pipeline

1. **Input Reading**: Uses `AVAssetReader` to read frames
2. **AI Upscaling**: Each frame is processed through CoreML/Vision
3. **Output Writing**: Uses `AVAssetWriter` with HEVC encoding
4. **Progress Tracking**: Reports progress compatible with existing UI

### Performance

- **GPU Acceleration**: Automatically uses Neural Engine on Apple Silicon or GPU on Intel Macs
- **Memory**: Processes frames sequentially to minimize memory usage
- **Speed**: Typically 1-5 seconds per frame depending on hardware

## Troubleshooting

### Model Not Found Error

If you see "Model file 'RealESRGAN_x4.mlmodel' not found":
1. Ensure the file is named exactly `RealESRGAN_x4.mlmodel`
2. Place it in `~/Library/Application Support/myUpscaler/Models/`
3. Restart the app

### Compilation Errors

If model compilation fails:
1. Verify the `.mlmodel` file is valid (try opening in Xcode)
2. Check macOS version (CoreML requires macOS 10.13+)
3. Ensure sufficient disk space for compiled model

### Performance Issues

- **Slow Processing**: Normal for AI upscaling; consider using smaller scale factors
- **Memory Warnings**: Process shorter videos or reduce batch size
- **GPU Not Used**: Check System Preferences > Energy Saver (disable "Automatic graphics switching" if available)

## Future Enhancements

Potential improvements:
- Support for 2x models (faster processing)
- Tile-based processing for very large images
- Multiple model selection (different quality/speed tradeoffs)
- Batch processing optimization

## App Store Compliance

✅ **Compliant**: This implementation uses only:
- Apple frameworks (CoreML, Vision, AVFoundation)
- No external binaries
- Models are data files (allowed)
- All processing happens on-device

❌ **Not Used**: 
- Vulkan (not supported on macOS/iOS)
- External ML frameworks (TensorFlow Lite, etc.)
- Pre-compiled binaries

