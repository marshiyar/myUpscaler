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
        // Saved enabled zero values are valid identities, not an instruction
        // to re-enable a filter with an interactive fallback strength.
        var zeroCandidate = source.configuration
        zeroCandidate.secondary.useDenoise = true
        zeroCandidate.secondary.denoiseStrength.text = "0"
        zeroCandidate.secondary.useDeblock = true
        zeroCandidate.secondary.deblockThresh.text = ""
        zeroCandidate.secondary.useDering = true
        zeroCandidate.secondary.deringStrength.text = "0"
        zeroCandidate.secondary.useSharpen = true
        zeroCandidate.secondary.sharpenMethod = "unsharp"
        zeroCandidate.secondary.usmRadius.text = "0"
        zeroCandidate.secondary.usmAmount.text = "0"
        zeroCandidate.secondary.usmThreshold.text = "0"
        zeroCandidate.secondary.useDeband = true
        zeroCandidate.secondary.debandStrength.text = "0"
        zeroCandidate.secondary.useGrain = true
        zeroCandidate.secondary.grainStrength.text = "0"
        source.replaceConfiguration(zeroCandidate)
        let zeroSnapshot = UpscaleSettingsSnapshot(settings: source)
        let zeroDecoded = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: JSONEncoder().encode(zeroSnapshot))
        for enabledBefore in [false, true] {
            let target = UpscaleSettings()
            var prior = target.configuration
            prior.secondary.useDenoise = enabledBefore
            prior.secondary.useDeblock = enabledBefore
            prior.secondary.useDering = enabledBefore
            prior.secondary.useSharpen = enabledBefore
            prior.secondary.useDeband = enabledBefore
            prior.secondary.useGrain = enabledBefore
            target.replaceConfiguration(prior)
            var count = 0
            let token = target.$configuration.dropFirst().sink { _ in count += 1 }
            zeroDecoded.apply(to: target)
            precondition(count == 1)
            precondition(target.configuration == zeroCandidate)
            precondition(UpscaleSettingsSnapshot(settings: target) == zeroDecoded)
            zeroDecoded.apply(to: target)
            precondition(count == 1, "Identical re-application should not publish")
            withExtendedLifetime(token) {}
        }
        source.resetToDefaults()
        source.secondary.useSharpen = true
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
        // Every stage field uses a distinct value to catch cross-stage DTO wiring.
        func sentinel(_ second: Bool) -> RestorationStage {
            RestorationStage(denoiser: second ? "hqdn3d" : "nlmeans",
                denoiseStrength: NumericDraft(text: second ? "4.2" : "2.3"),
                deblockMode: second ? "weak" : "strong",
                deblockThresh: NumericDraft(text: second ? "alpha=0.12" : "alpha=0.08"),
                useDering: !second, deringStrength: NumericDraft(text: second ? "0.7" : "0.3"),
                sharpenMethod: second ? "cas" : "unsharp",
                sharpenStrength: NumericDraft(text: second ? "0.42" : "0.31"),
                usmRadius: NumericDraft(text: second ? "9" : "7"),
                usmAmount: NumericDraft(text: second ? "1.7" : "1.4"),
                usmThreshold: NumericDraft(text: second ? "0.07" : "0.04"),
                debandMethod: second ? "f3kdb" : "gradfun",
                debandStrength: NumericDraft(text: second ? "0.025" : "1.5"),
                f3kdbRange: NumericDraft(text: second ? "17" : "13"),
                f3kdbY: NumericDraft(text: second ? "80" : "60"),
                f3kdbCbCr: NumericDraft(text: second ? "40" : "30"),
                grainStrength: NumericDraft(text: second ? "7" : "2"),
                useDeblock: second, useDenoise: !second, useSharpen: second,
                useDeband: !second, useGrain: second)
        }
        var distinct = SettingsConfiguration()
        distinct.primary = sentinel(false); distinct.secondary = sentinel(true)
        let original = UpscaleSettings(); original.replaceConfiguration(distinct)
        let serialized = try JSONEncoder().encode(UpscaleSettingsSnapshot(settings: original))
        let sentinelSnapshot = try JSONDecoder().decode(UpscaleSettingsSnapshot.self, from: serialized)
        for swap in [false, true] {
            var prior = SettingsConfiguration()
            prior.primary = swap ? distinct.secondary : RestorationStage.secondary
            prior.secondary = swap ? distinct.primary : RestorationStage()
            let destination = UpscaleSettings(); destination.replaceConfiguration(prior)
            var writes = 0
            let observation = destination.$configuration.dropFirst().sink { _ in writes += 1 }
            sentinelSnapshot.apply(to: destination)
            precondition(destination.configuration == distinct, "Every primary/secondary field must roundtrip")
            precondition(writes == 1)
            withExtendedLifetime(observation) {}
        }
        withExtendedLifetime(subscription) {}
        print("PASS typed groups, preserved drafts, transactional normalization, single-publication reset/preset, legacy JSON/target-independent zero preset identity, effective preview attenuation/radius")
    }
}
