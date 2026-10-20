import Foundation
import Synchronization

nonisolated private final class LogCapture: Sendable {
    private let lines = Mutex<[String]>([])
    func append(_ line: String) { lines.withLock { $0.append(line) } }
    func clear() { lines.withLock { $0.removeAll() } }
    func command() -> String {
        lines.withLock { values in
            let commands = values.filter { $0.hasPrefix("CMD: ") }
            precondition(commands.count == 1, "Expected one dry-run command: \(values)")
            precondition(!values.joined().contains("strength reduction"))
            return commands[0]
        }
    }
}

@main struct FinishingStrengthTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder); up60p_shutdown() }
        let input = folder.appendingPathComponent("fixture.png")
        // Dry-run logs the Rust engine's filter chain without decoding the file.
        try Data().write(to: input)
        up60p_set_dry_run(1)
        let logs = LogCapture()
        Up60PEngine.setLogHandler { logs.append($0) }
        func command(_ settings: UpscaleSettings) async throws -> String {
            logs.clear()
            try await Up60PEngine.shared.process(inputPath: input.path, settings: settings, outputDirectory: folder.path)
            return logs.command()
        }
        func assertOrder(_ command: String, _ fragments: [String]) {
            var remaining = command[...]
            for fragment in fragments {
                guard let range = remaining.range(of: fragment) else {
                    preconditionFailure("Missing or out-of-order \(fragment) in \(command)")
                }
                remaining = remaining[range.upperBound...]
            }
        }
        var cases = 0
        for firstMethod in ["cas", "unsharp"] {
            for secondMethod in ["cas", "unsharp"] {
                for deband in ["deband", "gradfun", "f3kdb"] {
                    var config = SettingsConfiguration()
                    config.upscaling.scaler = "lanczos"
                    config.codec.useHEVC = false
                    config.modes.noInterpolate = true; config.modes.noDecimate = true; config.modes.dryRun = true
                    config.color.noEq = true
                    config.primary.useDering = false; config.primary.useDeblock = false; config.primary.useGrain = false
                    config.secondary.useDering = false; config.secondary.useDeblock = false; config.secondary.useGrain = false
                    config.primary.denoiser = "bm3d"; config.secondary.denoiser = "bm3d"
                    config.primary.denoiseStrength.text = "2.3"; config.secondary.denoiseStrength.text = "4.2"
                    config.primary.useDenoise = true; config.secondary.useDenoise = true
                    config.primary.sharpenMethod = firstMethod; config.secondary.sharpenMethod = secondMethod
                    config.primary.useSharpen = true; config.secondary.useSharpen = true
                    config.primary.sharpenStrength.text = "0.31"; config.secondary.sharpenStrength.text = "0.42"
                    config.primary.usmRadius.text = "7"; config.secondary.usmRadius.text = "9"
                    config.primary.usmAmount.text = "1.4"; config.secondary.usmAmount.text = "1.7"
                    config.primary.debandMethod = deband; config.secondary.debandMethod = deband
                    config.primary.useDeband = true; config.secondary.useDeband = true
                    let strength = deband == "gradfun" ? "1.5" : "0.025"
                    config.primary.debandStrength.text = strength; config.secondary.debandStrength.text = strength
                    config.primary.f3kdbY.text = "60"; config.primary.f3kdbCbCr.text = "30"
                    config.secondary.f3kdbRange.text = "17"; config.secondary.f3kdbY.text = "80"; config.secondary.f3kdbCbCr.text = "40"
                    let settings = UpscaleSettings(); settings.replaceConfiguration(config)
                    let saved = UpscaleSettingsSnapshot(settings: settings)
                    let decoded = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: JSONEncoder().encode(saved))
                    let restored = UpscaleSettings(); decoded.apply(to: restored)
                    precondition(UpscaleSettingsSnapshot(settings: restored) == saved, "Preset must not rescale entered values")
                    let firstSharpen = firstMethod == "cas" ? "cas(0.31)" : "unsharp(7x7, amount=1.40"
                    let secondSharpen = secondMethod == "cas" ? "cas(0.42)" : "unsharp(9x9, amount=1.70"
                    let secondDeband = deband == "gradfun" ? "gradfun(1.50" : deband == "f3kdb" ? "deband(y=10.20, c=5.10, range=17, strict)" : "deband(y=6.3"
                    let actual = try await command(restored)
                    assertOrder(actual, ["bm3d(sigma=2.30)", "lanczos(", firstSharpen, "bm3d(sigma=4.20)", secondSharpen, secondDeband])
                    let preview = restored.makePreviewFilterParameters()
                    precondition(preview.denoiseStrength2 == 4.2)
                    precondition(secondMethod == "cas" ? preview.sharpenStrength2 == 0.42 : preview.usmAmount2 == 1.7 && preview.usmRadius2 == 9)
                    restored.primary.useDenoise = false; restored.primary.useSharpen = false; restored.primary.useDeband = false
                    let independent = try await command(restored)
                    assertOrder(independent, ["lanczos(", "bm3d(sigma=4.20)", secondSharpen, secondDeband])
                    precondition(!independent.contains("bm3d(sigma=2.30)"))
                    precondition(restored.makePreviewFilterParameters().denoiseStrength2 == preview.denoiseStrength2)
                    cases += 2
                }
            }
        }
        let settings = UpscaleSettings()
        settings.upscaling.scaler = "lanczos"; settings.codec.useHEVC = false
        settings.modes.noInterpolate = true; settings.modes.noDecimate = true; settings.modes.dryRun = true
        settings.primary.useDenoise = false; settings.primary.useSharpen = false; settings.primary.useDeband = false
        settings.primary.useDering = false; settings.primary.useDeblock = false; settings.primary.useGrain = false; settings.color.noEq = true
        settings.secondary.useDenoise = true; settings.secondary.denoiseStrength.text = "0"
        settings.secondary.useSharpen = true; settings.secondary.sharpenStrength.text = "0"
        settings.secondary.useDeband = true; settings.secondary.debandStrength.text = "0"
        settings.secondary.deringAmount = "0"
        let zero = try await command(settings)
        for filter in ["bm3d(", "dering(", "cas(", "unsharp(", "deband(", "gradfun("] {
            precondition(!zero.contains(filter), "Zero must bypass \(filter): \(zero)")
        }
        let snapshot = UpscaleSettingsSnapshot(settings: settings)
        let roundtrip = UpscaleSettings()
        try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: JSONEncoder().encode(snapshot)).apply(to: roundtrip)
        precondition(UpscaleSettingsSnapshot(settings: roundtrip) == snapshot)
        let zeroRoundtrip = try await command(roundtrip)
        precondition(zeroRoundtrip == zero, "Zero preset must preserve backend bypass")
        print("PASS \(cases + 2) native command cases: entered strengths, preset roundtrip, stage independence, filter order, zero bypass; preview parity")
    }
}
