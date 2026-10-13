import Foundation

extension UpscaleSettings {
    var effective10BitOutput: Bool {
        get { upscaling.scaler != "coreml" && codec.useHEVC && codec.use10Bit && !modes.pciSafe }
        set { codec.use10Bit = newValue }
    }

    var additionalDeblockMode: String {
        get { primary.useDeblock ? primary.deblockMode : "off" }
        set {
            guard newValue == "off" || deblockModes.contains(newValue) else { return }
            var next = primary
            next.useDeblock = newValue != "off"
            if next.useDeblock { next.deblockMode = newValue }
            primary = next
        }
    }

    var additionalDebandMethod: String {
        get { primary.useDeband ? primary.debandMethod : "off" }
        set {
            guard newValue == "off" || debandMethods.contains(newValue) else { return }
            var next = primary
            next.useDeband = newValue != "off"
            if next.useDeband { next.debandMethod = newValue }
            primary = next
        }
    }

    private func visibleAmount(_ draft: NumericDraft, enabled: Bool) -> String {
        !enabled && (draft.finiteValue ?? 0) > 0 ? "0" : draft.text
    }
    var additionalDebandAmount: String {
        get { visibleAmount(primary.debandStrength, enabled: primary.useDeband) }
        set {
            var next = primary
            next.debandStrength.text = newValue
            if let value = next.debandStrength.finiteValue { next.useDeband = value > 0 }
            primary = next
        }
    }
    var additionalGrainAmount: String {
        get { visibleAmount(primary.grainStrength, enabled: primary.useGrain) }
        set {
            var next = primary
            next.grainStrength.text = newValue
            if let value = next.grainStrength.finiteValue { next.useGrain = value > 0 }
            primary = next
        }
    }
    // F3KDB keeps its method-specific controls. A disabled legacy preset renders
    // neutral controls without rewriting its saved nonzero values on display.
    var additionalF3KDBStage: RestorationStage {
        get {
            var visible = primary
            visible.f3kdbRange.text = visibleAmount(primary.f3kdbRange, enabled: primary.useDeband)
            visible.f3kdbY.text = visibleAmount(primary.f3kdbY, enabled: primary.useDeband)
            visible.f3kdbCbCr.text = visibleAmount(primary.f3kdbCbCr, enabled: primary.useDeband)
            return visible
        }
        set {
            let oldVisible = additionalF3KDBStage
            var next = primary
            var changedValues: [Double] = []
            for path in [\RestorationStage.f3kdbRange, \.f3kdbY, \.f3kdbCbCr] {
                if newValue[keyPath: path] != oldVisible[keyPath: path] {
                    next[keyPath: path] = newValue[keyPath: path]
                    if let value = next[keyPath: path].finiteValue { changedValues.append(value) }
                }
            }
            if changedValues.contains(where: { $0 > 0 }) { next.useDeband = true }
            else if !changedValues.isEmpty && next.useDeband {
                next.useDeband = [next.f3kdbRange, next.f3kdbY, next.f3kdbCbCr].contains { ($0.finiteValue ?? 0) > 0 }
            }
            primary = next
        }
    }
    var interpolationChoice: String {
        get { modes.noInterpolate ? "off" : video.interpolation }
        set {
            guard ["off", "mci", "blend"].contains(newValue) else { return }
            var next = configuration
            next.modes.noInterpolate = newValue == "off"
            if newValue != "off" { next.video.interpolation = newValue }
            replaceConfiguration(next)
        }
    }
}

nonisolated enum DeblockThresholds {
    static func value(_ key: String, in text: String) -> String {
        text.split(separator: ":", omittingEmptySubsequences: false).compactMap { entry -> String? in
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces) == key else { return nil }
            return pair[1].trimmingCharacters(in: .whitespaces)
        }.last ?? ""
    }
    static func replacing(_ key: String, with value: String, in text: String) -> String {
        var entries = text.split(separator: ":", omittingEmptySubsequences: false).map(String.init).filter { entry in
            !entry.isEmpty && entry.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) != key
        }
        if !value.isEmpty { entries.append("\(key)=\(value)") }
        return entries.joined(separator: ":")
    }

    static func isValid(_ text: String) -> Bool {
        if text.isEmpty { return true }
        guard text.utf8.count < 64 else { return false }
        let entries = text.split(separator: ":", omittingEmptySubsequences: false)
        return entries.allSatisfy { entry in
            let pair = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return false }
            let key = pair[0].trimmingCharacters(in: .whitespaces)
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "alpha", "beta", "gamma", "delta":
                guard let number = Double(value), number.isFinite else { return false }
                return (0...1).contains(number)
            case "planes": return Int(value).map { (0...15).contains($0) } ?? false
            case "block": return Int(value).map { (4...512).contains($0) } ?? false
            case "filter": return ["weak", "strong", "0", "1"].contains(value)
            default: return false
            }
        }
    }
}
