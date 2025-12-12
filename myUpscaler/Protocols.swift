import Foundation
import AVFoundation

/// Protocol defining file system operations needed by the application
protocol FileSystemProtocol {
    var homeDirectoryForCurrentUser: URL { get }
    func fileExists(atPath path: String) -> Bool
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any]
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]
}

/// Protocol defining the interface for the upscaling engine
protocol EngineProtocol {
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws
    func cancel()
    func setLogHandler(_ handler: @escaping (String) -> Void)
}

/// Protocol defining video asset loading
protocol AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double
}

// MARK: - Default Implementations

extension FileManager: FileSystemProtocol {}

extension Up60PEngine: EngineProtocol {
    func setLogHandler(_ handler: @escaping (String) -> Void) {
        Up60PEngine.setLogHandler(handler)
    }
}

class AVAssetLoader: AssetLoaderProtocol {
    func loadDuration(from path: String) async throws -> Double {
        let ext = (path as NSString).pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            return 0.0
        }
        
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
}

