import Foundation
import Combine

extension UpscaleSettings {

    static func mock() -> UpscaleSettings {
        let mock = UpscaleSettings()

        mock.preview           = false
        mock.dryRun            = false

        mock.hwAccel           = mock.hwAccels.first ?? "none"
        mock.encoder           = mock.encoders.first ?? "libx264"
        mock.useHEVC           = false
        mock.use10Bit          = false
        mock.preset            = mock.presets.first ?? "medium"
        mock.threads           = "0"

        mock.crf               = 23
        mock.scaleFactor       = 2.0
        mock.fps               = "60"
        mock.interpolation     = mock.interpolations.first ?? "none"
        mock.x265AqMode        = "3"
        mock.x265PsyRd         = "2.0"
        mock.x265Deblock1      = "-2"
        mock.x265Deblock2      = "-2"

        mock.audioBitrate      = "192k"
        mock.movflags          = "+faststart"

        mock.scaler            = mock.scalers.first ?? "bicubic"
        mock.aiBackend         = mock.aiBackends.first ?? "none"
        mock.dnnBackend        = mock.dnnBackends.first ?? "none"
        mock.aiModelType       = mock.aiModelTypes.first ?? "none"
        mock.aiModelPath       = ""

        mock.denoiser          = mock.denoisers.first ?? "none"
        mock.denoiseStrength   = "0.5"
        mock.deblockMode       = mock.deblockModes.first ?? "none"
        mock.deblockThresh     = "0"
        mock.deringActive      = false
        mock.deringStrength    = "0.5"
        mock.sharpenMethod     = mock.sharpenMethods.first ?? "none"
        mock.usmRadius         = "5"
        mock.usmAmount         = "1.0"
        mock.usmThreshold      = "0.03"
        mock.sharpenStrength   = "0.25"
        mock.debandMethod      = mock.debandMethods.first ?? "none"
        mock.f3kdbRange        = "15"
        mock.f3kdbY            = "64"
        mock.f3kdbCbCr         = "64"
        mock.debandStrength    = "0.015"
        mock.grainStrength     = "1.0"
        mock.lutPath           = ""

        mock.useDenoise2       = false
        mock.denoiser2         = mock.denoisers.first ?? "none"
        mock.denoiseStrength2  = "0.5"
        mock.useDeblock2       = false
        mock.deblockMode2      = mock.deblockModes.first ?? "none"
        mock.deblockThresh2    = "0"
        mock.useDering2        = false
        mock.deringActive2     = false
        mock.deringStrength2   = "0.5"
        mock.useSharpen2       = false
        mock.sharpenMethod2    = mock.sharpenMethods.first ?? "none"
        mock.usmRadius2        = "5"
        mock.usmAmount2        = "1.0"
        mock.usmThreshold2     = "0.03"
        mock.sharpenStrength2  = "0.25"
        mock.useDeband2        = false
        mock.debandMethod2     = mock.debandMethods.first ?? "none"
        mock.f3kdbRange2       = "15"
        mock.f3kdbY2           = "64"
        mock.f3kdbCbCr2        = "64"
        mock.debandStrength2   = "0.015"
        mock.useGrain2         = false
        mock.grainStrength2    = "1.0"

        mock.noDeblock         = false
        mock.noDenoise         = false
        mock.noDecimate        = false
        mock.noInterpolate     = false
        mock.noSharpen         = false
        mock.noDeband          = false
        mock.noEq              = false
        mock.noGrain           = false
        mock.pciSafe           = false

        return mock
    }
}
