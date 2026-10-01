import Foundation
import Combine

extension UpscaleSettings {

    static func mock() -> UpscaleSettings {
        let mock = UpscaleSettings()

        mock.modes.preview           = false
        mock.modes.dryRun            = false

        mock.hardware.hwAccel           = mock.hwAccels.first ?? "none"
        mock.hardware.encoder           = mock.encoders.first ?? "libx264"
        mock.codec.useHEVC           = false
        mock.codec.use10Bit          = false
        mock.codec.preset            = mock.presets.first ?? "medium"
        mock.hardware.threads.text           = "0"

        mock.codec.crf               = 23
        mock.video.scaleFactor       = 2.0
        mock.video.fps.text               = "60"
        mock.video.interpolation     = mock.interpolations.first ?? "none"
        mock.codec.x265AqMode.text        = "3"
        mock.codec.x265PsyRd.text         = "2.0"
        mock.codec.x265Deblock1.text      = "-2"
        mock.codec.x265Deblock2.text      = "-2"

        mock.output.audioBitrate      = "192k"
        mock.output.movflags          = "+faststart"

        mock.upscaling.scaler            = mock.scalers.first ?? "bicubic"
        // Legacy AI metadata is retained for preset compatibility, not offered
        // as a selectable processing mode.
        mock.upscaling.aiModelPath       = ""

        mock.primary.denoiser          = mock.denoisers.first ?? "none"
        mock.primary.denoiseStrength.text   = "0.5"
        mock.primary.deblockMode       = mock.deblockModes.first ?? "none"
        mock.primary.deblockThresh.text     = "0"
        mock.primary.useDering      = false
        mock.primary.deringStrength.text    = "0.5"
        mock.primary.sharpenMethod     = mock.sharpenMethods.first ?? "none"
        mock.primary.usmRadius.text         = "5"
        mock.primary.usmAmount.text         = "1.0"
        mock.primary.usmThreshold.text      = "0.03"
        mock.primary.sharpenStrength.text   = "0.25"
        mock.primary.debandMethod      = mock.debandMethods.first ?? "none"
        mock.primary.f3kdbRange.text        = "15"
        mock.primary.f3kdbY.text            = "64"
        mock.primary.f3kdbCbCr.text         = "64"
        mock.primary.debandStrength.text    = "0.015"
        mock.primary.grainStrength.text     = "1.0"
//        mock.lutPath           = "" // LUT DEACTIVATED

        mock.secondary.useDenoise       = false
        mock.secondary.denoiser         = mock.denoisers.first ?? "none"
        mock.secondary.denoiseStrength.text  = "0.5"
        mock.secondary.useDeblock       = false
        mock.secondary.deblockMode      = mock.deblockModes.first ?? "none"
        mock.secondary.deblockThresh.text    = "0"
        mock.secondary.useDering        = false
        mock.secondary.useDering     = false
        mock.secondary.deringStrength.text   = "0.5"
        mock.secondary.useSharpen       = false
        mock.secondary.sharpenMethod    = mock.sharpenMethods.first ?? "none"
        mock.secondary.usmRadius.text        = "5"
        mock.secondary.usmAmount.text        = "1.0"
        mock.secondary.usmThreshold.text     = "0.03"
        mock.secondary.sharpenStrength.text  = "0.25"
        mock.secondary.useDeband        = false
        mock.secondary.debandMethod     = mock.debandMethods.first ?? "none"
        mock.secondary.f3kdbRange.text       = "15"
        mock.secondary.f3kdbY.text           = "64"
        mock.secondary.f3kdbCbCr.text        = "64"
        mock.secondary.debandStrength.text   = "0.015"
        mock.secondary.useGrain         = false
        mock.secondary.grainStrength.text    = "1.0"

        mock.primary.useDeblock = !(false)
        mock.primary.useDenoise = !(false)
        mock.modes.noDecimate        = false
        mock.modes.noInterpolate     = false
        mock.primary.useSharpen = !(false)
        mock.primary.useDeband = !(false)
        mock.color.noEq              = false
        mock.primary.useGrain = !(false)
        mock.modes.pciSafe           = false

        return mock
    }
}
