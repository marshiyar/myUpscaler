import AVFoundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif

struct CodecSupport {
    struct Decision {
        let useHEVC: Bool
        let message: String?
    }

    static func resolve(requestHEVC: Bool) -> Decision {
        guard requestHEVC else {
            return Decision(useHEVC: false, message: nil)
        }

        guard isHEVCHardwareEncodeAvailable else {
            return Decision(useHEVC: false, message: "HEVC encoding is not available on this Mac. Falling back to H.264 instead.\n")
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
