import AVFoundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif

nonisolated struct CodecSupport {
    static func isValidCRF(_ value: Double) -> Bool {
        value.isFinite && (0...51).contains(value)
    }

    /// Preserve the existing estimate, rejecting values that cannot form a bitrate.
    static func coreMLBitrate(pixelCount: Double, crf: Double) -> Int? {
        guard isValidCRF(crf), pixelCount.isFinite, pixelCount > 0 else { return nil }
        let value = pixelCount * 0.15 * (1.5 - crf / 51)
        guard value.isFinite, value >= 1, value < Double(Int.max) else { return nil }
        return Int(value)
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
        #if canImport(VideoToolbox)
        if #available(macOS 10.13, *) {
            var encoderList: CFArray?
            let status = VTCopyVideoEncoderList(nil, &encoderList)
            guard status == noErr, let array = encoderList as? [[String: Any]] else {
                return false
            }

            return array.contains { entry in
                (entry[kVTVideoEncoderList_CodecType as String] as? CMVideoCodecType) == kCMVideoCodecType_HEVC
            }
        }
        #endif
        return false
    }
}
