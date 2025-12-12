import XCTest
import Foundation

final class CodeQualityTests: XCTestCase {
    
    func testNoForceUnwraps() throws {
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        var url = URL(fileURLWithPath: currentDir)
        
        while !fileManager.fileExists(atPath: url.appendingPathComponent("myUpscaler.xcodeproj").path) {
            let parent = url.deletingLastPathComponent()
            if parent == url { break }
            url = parent
        }
        
        let sourceRoot = url.appendingPathComponent("myUpscaler")
        guard fileManager.fileExists(atPath: sourceRoot.path) else {
            print("Could not locate source root for quality checks. Skipped.")
            return
        }
        
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .pathKey]
        let enumerator = fileManager.enumerator(at: sourceRoot,
                                                includingPropertiesForKeys: resourceKeys,
                                                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        
        var violations: [String] = []
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            // Skip tests and generated files
            if fileURL.path.contains("Tests") || fileURL.path.contains("Generated") { continue }
            
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("!") && !trimmed.contains("!=") {
                    // Filter out comments
                    if trimmed.hasPrefix("//") { continue }
                    if line.range(of: #"[a-zA-Z0-9)\]]!"#, options: .regularExpression) != nil {
                        violations.append("\(fileURL.lastPathComponent):\(index + 1): \(trimmed)")
                    }
                }
            }
        }
        
        if !violations.isEmpty {
            XCTFail("Found force unwraps:\n" + violations.joined(separator: "\n"))
        }
    }
}

