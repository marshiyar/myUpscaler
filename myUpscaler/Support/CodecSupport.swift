import AVFoundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif

nonisolated struct CodecSupport {
    static func isValidCRF(_ value: Double) -> Bool {
        value.isFinite && (0...51).contains(value)
    }

    /// AVFoundation accepts bits per second; budget each source frame's pixels.
    static func coreMLBitrate(pixelCount: Double, crf: Double, framesPerSecond: Double) -> Int? {
        guard isValidCRF(crf), pixelCount.isFinite, pixelCount > 0,
              framesPerSecond.isFinite, framesPerSecond > 0 else { return nil }
        let value = pixelCount * framesPerSecond * 0.15 * (1.5 - crf / 51)
        guard value.isFinite, value >= 1, value < Double(Int.max) else { return nil }
        return Int(value)
    }

    static func encodingFrameRate(nominal: Double, minimumDurationSeconds: Double) -> Double? {
        if nominal.isFinite, nominal > 0 { return nominal }
        guard minimumDurationSeconds.isFinite, minimumDurationSeconds > 0 else { return nil }
        let rate = 1 / minimumDurationSeconds
        return rate.isFinite && rate > 0 ? rate : nil
    }

    static func coreMLSDRColorProperties(primaries: String?, transfer: String?, matrix: String?) -> [String: String]? {
        guard primaries == AVVideoColorPrimaries_ITU_R_709_2,
              transfer == AVVideoTransferFunction_ITU_R_709_2,
              matrix == AVVideoYCbCrMatrix_ITU_R_709_2 else { return nil }
        return [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
    }

    struct Decision {
        let useHEVC: Bool
        let message: String?
    }

    static func resolve(requestHEVC: Bool) -> Decision {
        guard requestHEVC else {
            return Decision(useHEVC: false, message: nil)
        }

        guard isHEVCHardwareEncodeAvailable else {
            return Decision(useHEVC: false, message: "HEVC not available. Using H.264 instead.\n")
        }

        return Decision(useHEVC: true, message: nil)
    }

    private static var isHEVCHardwareEncodeAvailable: Bool {
            var encoderList: CFArray?
            let status = VTCopyVideoEncoderList(nil, &encoderList)
            guard status == noErr, let array = encoderList as? [[String: Any]] else {
                return false
            }

            return array.contains { entry in
                (entry[kVTVideoEncoderList_CodecType as String] as? CMVideoCodecType) == kCMVideoCodecType_HEVC
            }
    }
}
