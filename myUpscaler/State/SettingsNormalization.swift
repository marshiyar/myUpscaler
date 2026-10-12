import Foundation
import Combine

/// Owns the automatic value/toggle normalization subscriptions. The settings
/// object remains the authoritative state; consumers do not keep duplicate flags.
nonisolated enum SettingsNormalization {
    static func install(on settings: UpscaleSettings) -> Set<AnyCancellable> {
        var cancellables = Set<AnyCancellable>()
        settings.$denoiser
            .sink { [weak settings] newDenoiser in
                guard let self = settings else { return }
                self.denoiseStrength = self.validateDenoiseStrength(self.denoiseStrength, forDenoiser: newDenoiser)
            }
            .store(in: &cancellables)

        settings.$denoiser2
            .sink { [weak settings] newDenoiser in
                guard let self = settings else { return }
                self.denoiseStrength2 = self.validateDenoiseStrength(self.denoiseStrength2, forDenoiser: newDenoiser)
            }
            .store(in: &cancellables)

        settings.$denoiseStrength2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDenoise2 = false
                }
            }
            .store(in: &cancellables)

        settings.$sharpenMethod
            .sink { [weak settings] newMethod in
                guard let self = settings else { return }
                self.sharpenStrength = self.validateSharpenStrength(self.sharpenStrength, method: newMethod)
            }
            .store(in: &cancellables)

        settings.$sharpenMethod2
            .sink { [weak settings] newMethod in
                guard let self = settings else { return }
                self.sharpenStrength2 = self.validateSharpenStrength2(self.sharpenStrength2, method: newMethod)
            }
            .store(in: &cancellables)

        settings.$debandMethod
            .sink { [weak settings] newMethod in
                guard let self = settings else { return }
                self.debandStrength = self.validateDebandStrength(self.debandStrength)
            }
            .store(in: &cancellables)

        settings.$debandMethod2
            .sink { [weak settings] newMethod in
                guard let self = settings else { return }
                self.debandStrength2 = self.validateDebandStrength(self.debandStrength2)
            }
            .store(in: &cancellables)

        settings.$deringStrength
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.deringActive = false
                }
            }
            .store(in: &cancellables)

        settings.$deringActive
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZero(self.deringStrength) {
                    self.deringStrength = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)

        // Note: denoiseStrength2 validation is handled above in the combined observer

        settings.$useDenoise2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZero(self.denoiseStrength2) {
                    self.denoiseStrength2 = self.defaultDenoiseStrength2String
                }
            }
            .store(in: &cancellables)

        settings.$deblockThresh2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if value.isEmpty || value == "0" || (Double(value) ?? 0) == 0 {
                    self.useDeblock2 = false
                }
            }
            .store(in: &cancellables)


        settings.$useDeblock2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZeroOrEmpty(self.deblockThresh2) {
                    self.deblockThresh2 = self.defaultDeblockThreshString
                }
            }
            .store(in: &cancellables)


        settings.$deringStrength2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDering2 = false
                    self.deringActive2 = false
                }
            }
            .store(in: &cancellables)


        settings.$useDering2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZero(self.deringStrength2) {
                    self.deringStrength2 = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)


        settings.$deringActive2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZero(self.deringStrength2) {
                    self.deringStrength2 = self.defaultDeringStrengthString
                }
            }
            .store(in: &cancellables)


        settings.$sharpenStrength2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useSharpen2 = false
                }
            }
            .store(in: &cancellables)


        Publishers.CombineLatest3(settings.$usmRadius2, settings.$usmAmount2, settings.$usmThreshold2)
            .sink { [weak settings] radius, amount, threshold in
                guard let self = settings else { return }
                if self.sharpenMethod2 == "unsharp" {
                    let radiusVal = Double(radius) ?? 0
                    let amountVal = Double(amount) ?? 0
                    let thresholdVal = Double(threshold) ?? 0
                    if radiusVal == 0 && amountVal == 0 && thresholdVal == 0 {
                        self.useSharpen2 = false
                    }
                }
            }
            .store(in: &cancellables)


        settings.$useSharpen2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.sharpenMethod2 == "cas" {
                    if self.isZero(self.sharpenStrength2) {
                        self.sharpenStrength2 = self.defaultSharpenStrength2String
                    }
                } else if self.sharpenMethod2 == "unsharp" {
                    let radiusVal = Double(self.usmRadius2) ?? 0
                    let amountVal = Double(self.usmAmount2) ?? 0
                    let thresholdVal = Double(self.usmThreshold2) ?? 0
                    if radiusVal == 0 && amountVal == 0 && thresholdVal == 0 {
                        self.usmRadius2 = self.defaultUsmRadius2String
                        self.usmAmount2 = self.defaultUsmAmount2String
                        self.usmThreshold2 = self.defaultUsmThreshold2String
                    }
                }
            }
            .store(in: &cancellables)

        settings.$debandStrength2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useDeband2 = false
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(settings.$f3kdbRange2, settings.$f3kdbY2, settings.$f3kdbCbCr2)
            .sink { [weak settings] range, y, cbcr in
                guard let self = settings else { return }
                if self.debandMethod2 == "f3kdb" {
                    let rangeVal = Double(range) ?? 0
                    let yVal = Double(y) ?? 0
                    let cbcrVal = Double(cbcr) ?? 0
                    if rangeVal == 0 && yVal == 0 && cbcrVal == 0 {
                        self.useDeband2 = false
                    }
                }
            }
            .store(in: &cancellables)

        settings.$useDeband2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.debandMethod2 == "f3kdb" {
                    let rangeVal = Double(self.f3kdbRange2) ?? 0
                    let yVal = Double(self.f3kdbY2) ?? 0
                    let cbcrVal = Double(self.f3kdbCbCr2) ?? 0
                    if rangeVal == 0 && yVal == 0 && cbcrVal == 0 {
                        self.f3kdbRange2 = self.defaultF3kdbRange2String
                        self.f3kdbY2 = self.defaultF3kdbY2String
                        self.f3kdbCbCr2 = self.defaultF3kdbCbCr2String
                    }
                } else {
                    if self.isZero(self.debandStrength2) {
                        self.debandStrength2 = self.defaultDebandStrength2String
                    }
                }
            }
            .store(in: &cancellables)

        settings.$grainStrength2
            .sink { [weak settings] value in
                guard let self = settings else { return }
                if let numValue = Double(value), numValue == 0 {
                    self.useGrain2 = false
                }
            }
            .store(in: &cancellables)

        settings.$useGrain2
            .sink { [weak settings] isOn in
                guard let self = settings, isOn else { return }
                if self.isZero(self.grainStrength2) {
                    self.grainStrength2 = self.defaultGrainStrength2String
                }
            }
            .store(in: &cancellables)
        return cancellables
    }
}
