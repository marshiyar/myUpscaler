import Foundation
import Combine

@main struct Tests {
    static func main() throws {
        let settings = UpscaleSettings()
        let initial = settings.configuration
        var publications = 0
        let subscription = settings.$configuration.dropFirst().sink { _ in publications += 1 }
        settings.primary.denoiseStrength.text = "-"
        precondition(settings.primary.denoiseStrength.text == "-")
        settings.secondary.deblockThresh.text = "0."
        precondition(settings.secondary.deblockThresh.text == "0.")
        settings.secondary.useDering = true
        settings.secondary.deringStrength.text = "0"
        precondition(!settings.secondary.useDering)
        settings.secondary.useDering = true
        precondition(settings.secondary.deringStrength.text == "0.5")
        settings.secondary.denoiseStrength.text = "-"
        precondition(settings.secondary.denoiseStrength.text == "-")
        settings.secondary.denoiser = "nlmeans"
        precondition(settings.secondary.denoiseStrength.text == "1.00")
        publications = 0
        settings.resetToDefaults()
        precondition(publications == 1 && settings.configuration == initial)
        let source = UpscaleSettings()
        source.primary.sharpenMethod = "unsharp"
        source.primary.sharpenStrength.text = "0.7000"
        source.codec.crf = 17
        source.primary.useDenoise = false
        source.secondary.useSharpen = true
        source.secondary.sharpenStrength.text = "0.7"
        source.video.scaleFactor = 4
        let snapshot = UpscaleSettingsSnapshot(settings: source)
        let decoded = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: JSONEncoder().encode(snapshot))
        publications = 0
        decoded.apply(to: settings)
        precondition(publications == 1)
        precondition(UpscaleSettingsSnapshot(settings: settings) == decoded)
        precondition(!settings.primary.useDenoise && settings.secondary.useSharpen)
        source.primary.sharpenMethod = "cas"
        source.primary.useSharpen = true
        source.secondary.sharpenStrength.text = "0.6"
        precondition(abs(source.makePreviewFilterParameters().sharpenStrength2 - 0.36) < 0.00001)
        source.primary.useSharpen = false
        precondition(source.makePreviewFilterParameters().sharpenStrength2 == 0.6)
        let before = source.makePreviewFilterParameters()
        source.primary.usmThreshold.text = "0.99"
        precondition(source.makePreviewFilterParameters() == before)
        for (input, expected) in [("4.9",3.0),("nan",3),("1e99",23),("inf",3),("0",3)] {
            precondition(UpscaleSettings.unsharpMatrixSize(input) == expected)
        }
        withExtendedLifetime(subscription) {}
        print("PASS typed groups, preserved drafts, transactional normalization, single-publication reset/preset, legacy JSON, effective preview attenuation/radius")
    }
}
