import Foundation
import Combine

@main struct PresetPersistenceTests {
    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("preset-persistence-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("presets.json")

        // An unreadable file is kept aside, reported, and not overwritten by the next save.
        let garbage = Data("not json".utf8)
        try garbage.write(to: file)
        let store = PresetStore(storageURL: file)
        precondition(store.presets.isEmpty)
        precondition(store.storageNotice?.contains("presets.bad") == true)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        precondition(try Data(contentsOf: directory.appendingPathComponent("presets.bad")) == garbage)
        store.add(name: "Fresh", settings: UpscaleSettings())
        precondition(try Data(contentsOf: directory.appendingPathComponent("presets.bad")) == garbage)
        precondition(PresetStore(storageURL: file).presets.map(\.name) == ["Fresh"])
        store.dismissNotice()
        precondition(store.storageNotice == nil)

        // A second unreadable file does not replace the first one kept aside.
        try garbage.write(to: file)
        _ = PresetStore(storageURL: file)
        precondition(FileManager.default.fileExists(atPath: directory.appendingPathComponent("presets.bad.2").path))

        // A write error is reported instead of ignored.
        let missing = directory.appendingPathComponent("no-such-folder/presets.json")
        let failing = PresetStore(storageURL: missing)
        failing.add(name: "Lost", settings: UpscaleSettings())
        precondition(failing.storageNotice?.contains("could not be saved") == true)
        print("PASS: unreadable presets are kept aside and reported; write errors are reported")
    }
}
