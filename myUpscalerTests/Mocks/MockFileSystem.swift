import Foundation
@testable import myUpscaler

class MockFileSystem: FileSystemProtocol {
    var homeDirectoryForCurrentUser: URL = URL(fileURLWithPath: "/Users/test")
    
    var existingFiles: [String: [FileAttributeKey: Any]] = [:]
    var directories: Set<String> = []
    
    var createDirectoryError: Error?
    var attributesError: Error?
    
    func fileExists(atPath path: String) -> Bool {
        return existingFiles.keys.contains(path)
    }
    
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey : Any] {
        if let error = attributesError {
            throw error
        }
        guard let attributes = existingFiles[path] else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: nil)
        }
        return attributes
    }
    
    func createDirectory(atPath path: String, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey : Any]?) throws {
        if let error = createDirectoryError {
            throw error
        }
        directories.insert(path)
    }
    
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        if directory == .downloadsDirectory {
            return [URL(fileURLWithPath: "/Users/test/Downloads")]
        }
        return []
    }
    
    // Helper to setup test state
    func mockFile(atPath path: String, size: Int64 = 1024) {
        existingFiles[path] = [.size: size]
    }
}

