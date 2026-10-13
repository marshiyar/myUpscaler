import Foundation
import Darwin

/// A frozen folder job: no engine independently recurses or chooses destination names.
nonisolated struct BatchPlan: Sendable {
    struct Item: Sendable {
        let input: URL
        let output: URL
    }
    let outputRoot: URL
    let items: [Item]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"]
    static let videoExtensions: Set<String> = ["mp4", "mkv", "mov"]

    static func make(input: URL, outputFolder: URL, coreML: Bool) throws -> BatchPlan {
        let fm = FileManager.default
        let source = input.standardizedFileURL.resolvingSymlinksInPath()
        let outputParent = outputFolder.standardizedFileURL.resolvingSymlinksInPath()
        let root = outputParent.appendingPathComponent(source.lastPathComponent + "_[restored]", isDirectory: true)
        guard source.path != root.path else { throw Failure("Input and batch output folders must differ.") }
        var folders: [(URL, String)] = [(source, "")]
        var visited = 0
        var items: [Item] = []
        var destinations = Set<String>()
        while let (folder, prefix) = folders.popLast() {
            try Task.checkCancellation()
            let children = try fm.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
            for child in children {
                try Task.checkCancellation()
                visited += 1
                guard visited <= 100_000 else { throw Failure("Folder export is limited to 100,000 directory entries per job.") }
                let relative = prefix.isEmpty ? child.lastPathComponent : prefix + "/" + child.lastPathComponent
                // Keep the relative name explicitly: enumerator URLs may canonicalize /var to /private/var.
                let url = source.appendingPathComponent(relative).standardizedFileURL
                let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                let nestedOutput = outputParent.path != source.path && outputParent.path.hasPrefix(source.path + "/") && url.path == outputParent.path
                if values.isSymbolicLink == true || url.path == root.path || nestedOutput { continue }
                if values.isDirectory == true { folders.append((url, relative)); continue }
                guard values.isRegularFile == true else { continue }
                let ext = url.pathExtension.lowercased()
                guard imageExtensions.contains(ext) || videoExtensions.contains(ext) else { continue }

                let relativeParent = (relative as NSString).deletingLastPathComponent

                let name = url.deletingPathExtension().lastPathComponent
                + "_[restored]." + (imageExtensions.contains(ext) ? "png" : "mp4")

                let output = root.appendingPathComponent(relativeParent, isDirectory: true).appendingPathComponent(name).standardizedFileURL

                // Conservatively reject aliases even on case-sensitive volumes.
                guard destinations.insert(output.path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                    throw Failure("Two inputs map to the same output: \(output.path).")
                }
                try checkDestination(output, root: root)
                items.append(Item(input: url, output: output))
            }
        }
        guard !items.isEmpty else { throw Failure("No supported media files found in the folder.") }
        return BatchPlan(outputRoot: root, items: items.sorted { $0.input.path < $1.input.path })
    }

    static func checkDestination(_ output: URL, root: URL) throws {
        let fm = FileManager.default
        guard (try? fm.attributesOfItem(atPath: output.path)) == nil else {
            throw Failure("Output already exists; choose another output folder: \(output.path).")
        }
        let rootPath = root.standardizedFileURL.path
        guard output.standardizedFileURL.path.hasPrefix(rootPath + "/") else { throw Failure("Output escapes the batch folder.") }
        var parent = output.deletingLastPathComponent().standardizedFileURL
        while parent.path == rootPath || parent.path.hasPrefix(rootPath + "/") {
            if let attributes = try? fm.attributesOfItem(atPath: parent.path),
               attributes[.type] as? FileAttributeType != .typeDirectory {
                throw Failure("Output parent is not a regular directory: \(parent.path).")
            }
            if parent.path == rootPath { break }
            let next = parent.deletingLastPathComponent().standardizedFileURL
            guard next.path != parent.path else { throw Failure("Invalid output parent path.") }
            parent = next
        }
    }
    static func commit(staged: URL, output: URL) throws {
        // Same-parent staging permits an atomic rename. RENAME_EXCL protects a
        // destination created after preflight without a check/rename race.
        let result = staged.path.withCString { source in
            output.path.withCString { destination in renamex_np(source, destination, UInt32(RENAME_EXCL)) }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }
}
