import Foundation

/// Normalize a complete candidate before its single publication. Draft text is
/// never rewritten while typing; selecting a different algorithm validates it.
nonisolated enum SettingsNormalization {
    static func normalize(_ next: inout SettingsConfiguration, previous: SettingsConfiguration, validateMethodChanges: Bool = true) {
        normalizeStage(&next.primary, previous: previous.primary, secondary: false, validateMethodChanges: validateMethodChanges)
        normalizeStage(&next.secondary, previous: previous.secondary, secondary: true, validateMethodChanges: validateMethodChanges)
    }

    private static func normalizeStage(_ next: inout RestorationStage, previous: RestorationStage, secondary: Bool, validateMethodChanges: Bool) {
        let defaults = RestorationStage()
        if validateMethodChanges && next.denoiser != previous.denoiser {
            let range: ClosedRange<Double>
            let fallback: Double
            switch next.denoiser {
            case "hqdn3d": range = 1...10; fallback = 4
            case "nlmeans": range = 1...30; fallback = 1
            case "atadenoise": range = 1...20; fallback = 9
            default: range = 0...20; fallback = 2.5
            }
            if !(next.denoiser == "bm3d" && next.denoiseStrength.text.lowercased() == "auto") {
                next.denoiseStrength.text = String(format: "%.2f", clamp(next.denoiseStrength.finiteValue ?? fallback, range))
            }
        }
        if validateMethodChanges && next.sharpenMethod != previous.sharpenMethod {
            let unsharp = next.sharpenMethod == "unsharp"
            next.sharpenStrength.text = String(format: "%.2f", clamp(next.sharpenStrength.finiteValue ?? (unsharp ? 1 : 0.25), unsharp ? -2...5 : 0...1))
        }
        if validateMethodChanges && next.debandMethod != previous.debandMethod {
            let gradfun = next.debandMethod == "gradfun"
            next.debandStrength.text = String(clamp(next.debandStrength.finiteValue ?? (gradfun ? 1.2 : 0.015), gradfun ? 0.51...64 : 0...0.1))
        }
        reconcile(&next.useDering, previous: previous.useDering, draft: &next.deringStrength, old: previous.deringStrength, fallback: defaults.deringStrength.text)
        guard secondary else { return }
        reconcile(&next.useDenoise, previous: previous.useDenoise, draft: &next.denoiseStrength, old: previous.denoiseStrength, fallback: next.denoiser == "hqdn3d" ? "4.0" : next.denoiser == "nlmeans" ? "1.0" : next.denoiser == "atadenoise" ? "9.0" : "2.5")
        reconcile(&next.useDeblock, previous: previous.useDeblock, draft: &next.deblockThresh, old: previous.deblockThresh, fallback: "0.5", emptyIsZero: true)
        if next.sharpenMethod == "cas" {
            reconcile(&next.useSharpen, previous: previous.useSharpen, draft: &next.sharpenStrength, old: previous.sharpenStrength, fallback: defaults.sharpenStrength.text)
        } else {
            if next.useSharpen && !previous.useSharpen && allZero([next.usmRadius, next.usmAmount, next.usmThreshold]) {
                next.usmRadius = defaults.usmRadius; next.usmAmount = defaults.usmAmount; next.usmThreshold = defaults.usmThreshold
            } else if [next.usmRadius, next.usmAmount, next.usmThreshold] != [previous.usmRadius, previous.usmAmount, previous.usmThreshold] && allZero([next.usmRadius, next.usmAmount, next.usmThreshold]) { next.useSharpen = false }
        }
        if next.debandMethod == "f3kdb" {
            if next.useDeband && !previous.useDeband && allZero([next.f3kdbRange, next.f3kdbY, next.f3kdbCbCr]) {
                next.f3kdbRange = defaults.f3kdbRange; next.f3kdbY = defaults.f3kdbY; next.f3kdbCbCr = defaults.f3kdbCbCr
            } else if [next.f3kdbRange, next.f3kdbY, next.f3kdbCbCr] != [previous.f3kdbRange, previous.f3kdbY, previous.f3kdbCbCr] && allZero([next.f3kdbRange, next.f3kdbY, next.f3kdbCbCr]) { next.useDeband = false }
        } else {
            reconcile(&next.useDeband, previous: previous.useDeband, draft: &next.debandStrength, old: previous.debandStrength, fallback: next.debandMethod == "gradfun" ? "1.2" : defaults.debandStrength.text)
        }
        reconcile(&next.useGrain, previous: previous.useGrain, draft: &next.grainStrength, old: previous.grainStrength, fallback: defaults.grainStrength.text)
    }
    private static func reconcile(_ enabled: inout Bool, previous: Bool, draft: inout NumericDraft, old: NumericDraft, fallback: String, emptyIsZero: Bool = false) {
        let zero = draft.finiteValue == 0 || (emptyIsZero && draft.text.isEmpty)
        if enabled && !previous && zero { draft.text = fallback }
        else if draft != old && zero { enabled = false }
    }
    private static func allZero(_ drafts: [NumericDraft]) -> Bool { drafts.allSatisfy { $0.finiteValue == 0 } }
    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double { max(range.lowerBound, min(range.upperBound, value)) }
}
