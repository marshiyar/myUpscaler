import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Shared input policy for import, preview and processing.
nonisolated enum VideoInput {
    static let message = "Choose a video file or a folder containing videos. Images are not supported."
    private static let videoExtensions = ["mp4", "mov", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "ts", "mts", "m2ts"]
    static let contentTypes: [UTType] = [.movie] + videoExtensions.compactMap { UTType(filenameExtension: $0) }

    static func hasVideoExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) || UTType(filenameExtension: ext)?.conforms(to: .movie) == true
    }

    static func hasImageExtension(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp", "gif", "heic", "heif", "avif", "ico"].contains(ext)
            || UTType(filenameExtension: ext)?.conforms(to: .image) == true
    }

    static func isVideo(_ url: URL) -> Bool {
        guard url.isFileURL, hasVideoExtension(url),
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { return false }
        // An image renamed to .mp4 must not enter FFmpeg's still-image path.
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetType(source) != nil {
            return false
        }
        return true
    }

    static func acceptsSelection(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return true }
        return isVideo(url)
    }
}
