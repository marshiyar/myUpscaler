import Foundation
import CoreImage
import CoreGraphics
import Metal

private struct KernelCase {
    let name: String
    let samples: Int
    let parameters: [[Float]]
}

private let cases: [KernelCase] = [
    .init(name: "linearize_srgb", samples: 1, parameters: [[0], [0.65], [1], [2]]),
    .init(name: "encode_srgb", samples: 1, parameters: [[0], [0.65], [1], [2]]),
    .init(name: "tone_map_reinhard", samples: 1, parameters: [[0], [1], [3]]),
    .init(name: "gamma_correct_blend", samples: 2, parameters: [[-0.25], [0], [0.35], [1], [1.25]]),
    .init(name: "cas_sharpen", samples: 1, parameters: [[0], [0.5], [1]]),
    .init(name: "deband_dither", samples: 1, parameters: [[0.02, 0], [0.02, 0.45], [0.1, 1]]),
    .init(name: "bilateral_denoise", samples: 1, parameters: [[0, 0.1], [2, 0], [1.5, 0.08], [2, 0.2]]),
    .init(name: "drift_guard", samples: 2, parameters: [[0.05, 0], [0.05, 0.75], [0.1, 1]]),
    .init(name: "unsharp_mask", samples: 1, parameters: [[1, 0, 0.02], [1, 0.5, 0.02], [2, 2, 0.05], [3, 1, 0.1]]),
    .init(name: "laplacian_sharpen", samples: 1, parameters: [[0], [0.75], [1]]),
    .init(name: "median_denoise", samples: 1, parameters: [[]]),
    .init(name: "blue_noise_deband", samples: 1, parameters: [[0.02, 0], [0.02, 0.5], [0.1, 1]]),
    .init(name: "dehalo", samples: 1, parameters: [[0], [0.45], [1]]),
    .init(name: "moire_suppress", samples: 1, parameters: [[0], [0.45], [1]]),
    .init(name: "premultiply_alpha", samples: 1, parameters: [[]]),
    .init(name: "unpremultiply_alpha", samples: 1, parameters: [[]]),
    .init(name: "mask_feather", samples: 1, parameters: [[0], [1], [3], [7]]),
    .init(name: "mask_dilate", samples: 1, parameters: [[0], [1], [3], [7]]),
    .init(name: "mask_erode", samples: 1, parameters: [[0], [1], [3], [7]]),
    .init(name: "hann_feather_tile", samples: 1, parameters: [[40, 32, 0], [40, 32, 6], [40, 32, 24]]),
    .init(name: "temporal_smooth", samples: 2, parameters: [[0], [0.35], [1]])
]

private struct Failure: Error, CustomStringConvertible {
    let description: String
}

private func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(description: message) }
}

@main
private enum ShaderKernelRegression {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw Failure(description: "No Metal GPU is accessible. Run this test with GPU access; compilation alone is not a runtime pass.")
        }
        let extent = CGRect(x: 0, y: 0, width: 40, height: 32)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)!
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(mtlDevice: device, options: [
            .workingColorSpace: linear,
            .outputColorSpace: srgb,
            .cacheIntermediates: false
        ])
        let splitURL = Bundle.main.url(forResource: "default", withExtension: "metallib")
        try require(splitURL != nil, "Bundle.main did not find default.metallib")
        let splitData = try Data(contentsOf: splitURL!)
        let expectedNames = cases.map(\.name).sorted()
        try require(CIKernel.kernelNames(fromMetalLibraryData: splitData).sorted() == expectedNames,
                    "Split metallib entrypoint set differs from the 21-kernel ABI")

        // This registry is extracted from the current app source by run.py, without edits.
        let registry = CoreMLEngine.ShaderRegistry.shared
        let registryKernels: [CIKernel?] = [
            registry.linearizeKernel, registry.encodeSrgbKernel, registry.toneMapKernel,
            registry.gammaBlendKernel, registry.casKernel, registry.debandKernel,
            registry.bilateralKernel, registry.driftGuardKernel, registry.unsharpKernel,
            registry.laplacianKernel, registry.medianKernel, registry.blueNoiseDebandKernel,
            registry.dehaloKernel, registry.moireKernel, registry.premultiplyKernel,
            registry.unpremultiplyKernel, registry.maskFeatherKernel, registry.maskDilateKernel,
            registry.maskErodeKernel, registry.hannFeatherKernel, registry.temporalSmoothKernel
        ]
        try require(registryKernels.compactMap { $0?.name }.sorted() == expectedNames,
                    "App ShaderRegistry did not load every kernel from Bundle.main")

        var baselineData: Data?
        if CommandLine.arguments.count > 1 {
            baselineData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            try require(CIKernel.kernelNames(fromMetalLibraryData: baselineData!).sorted() == expectedNames,
                        "Baseline metallib entrypoint set differs from the 21-kernel ABI")
        }
        let fixtures = (0..<3).map { fixture($0, extent: extent, colorSpace: srgb) }
        let baselineFixtures = (0..<3).map { fixture(($0 + 1) % 3, extent: extent, colorSpace: srgb) }
        var renderCount = 0
        var maxDifference: Float = 0
        var exactComparisons = 0
        let tolerance: Float = 0.000001
        for (index, item) in cases.enumerated() {
            let splitKernel = registryKernels[index]!
            let baselineKernel = try baselineData.map { try CIKernel(functionName: item.name, fromMetalLibraryData: $0) }
            for fixtureIndex in fixtures.indices {
                for parameters in item.parameters {
                    var arguments: [Any] = [fixtures[fixtureIndex].clampedToExtent()]
                    if item.samples == 2 { arguments.append(baselineFixtures[fixtureIndex].clampedToExtent()) }
                    arguments.append(contentsOf: parameters.map { NSNumber(value: $0) })
                    let split = try render(splitKernel, arguments: arguments, extent: extent,
                                           context: context, colorSpace: srgb)
                    renderCount += 1
                    try require(split.allSatisfy(\.isFinite), "Nonfinite output: \(item.name), fixture \(fixtureIndex), \(parameters)")
                    if let baselineKernel {
                        let baseline = try render(baselineKernel, arguments: arguments, extent: extent,
                                                  context: context, colorSpace: srgb)
                        try require(baseline.allSatisfy(\.isFinite), "Nonfinite baseline: \(item.name)")
                        let difference = zip(split, baseline).map { abs($0 - $1) }.max()!
                        maxDifference = max(maxDifference, difference)
                        if split == baseline { exactComparisons += 1 }
                        try require(difference <= tolerance,
                                    "Output changed: \(item.name), fixture \(fixtureIndex), \(parameters), max difference \(difference)")
                    }
                }
            }
        }
        let report: [String: Any] = [
            "gpu": device.name, "entrypoints": expectedNames,
            "registryLoaded": registryKernels.count, "splitRenders": renderCount,
            "baselineCompared": baselineData != nil, "exactComparisons": exactComparisons,
            "maximumAbsoluteFloatDifference": maxDifference, "tolerance": tolerance,
            "fixtureSize": [40, 32], "fixtureCount": fixtures.count,
            "format": "RGBAf", "workingColorSpace": "linearSRGB", "outputColorSpace": "sRGB"
        ]
        let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        print(String(decoding: json, as: UTF8.self))
    }

    private static func fixture(_ kind: Int, extent: CGRect, colorSpace: CGColorSpace) -> CIImage {
        let width = Int(extent.width), height = Int(extent.height)
        var pixels = [Float]()
        pixels.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let alpha: Float = kind == 2 ? Float((x + y) % 5) / 4 : 1
                let red: Float
                let green: Float
                let blue: Float
                switch kind {
                case 0:
                    red = Float(x) / Float(width - 1)
                    green = Float(y) / Float(height - 1)
                    blue = Float((x / 5 + y / 4) % 8) / 7
                case 1:
                    red = (x + y) % 2 == 0 ? 0.95 : 0.05
                    green = x < width / 2 ? 0.1 : 0.9
                    blue = y % 3 == 0 ? 0.8 : 0.2
                default:
                    red = 0.48 + Float(x / 4) * 0.004
                    green = 0.5
                    blue = 0.52 - Float(y / 4) * 0.004
                }
                pixels.append(contentsOf: [red * alpha, green * alpha, blue * alpha, alpha])
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        return CIImage(bitmapData: data, bytesPerRow: width * 4 * MemoryLayout<Float>.size,
                       size: extent.size, format: .RGBAf, colorSpace: colorSpace)
    }

    private static func render(_ kernel: CIKernel, arguments: [Any], extent: CGRect,
                               context: CIContext, colorSpace: CGColorSpace) throws -> [Float] {
        guard let image = kernel.apply(extent: extent,
                                       roiCallback: { _, rect in rect.insetBy(dx: -3, dy: -3) },
                                       arguments: arguments) else {
            throw Failure(description: "Kernel application failed: \(kernel.name)")
        }
        var pixels = [Float](repeating: .nan, count: Int(extent.width * extent.height) * 4)
        pixels.withUnsafeMutableBufferPointer { buffer in
            context.render(image, toBitmap: buffer.baseAddress!,
                           rowBytes: Int(extent.width) * 4 * MemoryLayout<Float>.size,
                           bounds: extent, format: .RGBAf, colorSpace: colorSpace)
        }
        return pixels
    }
}
