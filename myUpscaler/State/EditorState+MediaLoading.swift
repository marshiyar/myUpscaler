import AppKit
import AVFoundation

// Request handles and generations belong to EditorState. Each publication below
// must validate its captured generation before changing observable selection state.
extension EditorState {
    // MARK: - Load Thumbnail
    func loadThumbnail(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            if let image = NSImage(contentsOf: url) {
                self.installOriginal(image)
                self.videoAsset = nil
                return
            }
        }

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        let generation = mediaGeneration
        let selectedFrame = frameGeneration
        thumbnailTask?.cancel()
        thumbnailTask = Task {
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await imageGenerator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: .zero)

                await MainActor.run {
                    guard generation == self.mediaGeneration, selectedFrame == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(nsImage)
                }
            } catch {
                print("Thumbnail error: \(error)")
            }
        }
    }

    // MARK: -  Load Timeline
    func loadTimeline(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        if ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "webp"].contains(ext) {
            if let image = NSImage(contentsOf: url) {
                self.videoFPS = 0
                self.totalFrames = 1
                self.timelineFrames = [image]
                self.timelineFrameTimes = [0.0]
                return
            }
        }

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        let generation = mediaGeneration
        timelineTask?.cancel()
        timelineTask = Task {
            guard let track = try? await asset.loadTracks(withMediaType: .video).first else { return }

            guard let durationTime = try? await asset.load(.duration) else { return }
            let duration = durationTime.seconds

            let fpsFloat = try? await track.load(.nominalFrameRate)
            let reportedFPS = Double(fpsFloat ?? 30.0)
            let fps = reportedFPS.isFinite && reportedFPS > 0 ? reportedFPS : 30.0
            guard duration.isFinite, duration >= 0, !Task.isCancelled else { return }

            await MainActor.run {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                self.videoFPS = fps
                self.totalFrames = Int(duration * fps)
                self.timelineFrames.removeAll()
                self.timelineFrameTimes.removeAll()
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 200, height: 200)

            // Prepare times - limit to 50 frames for better memory performance
            var times: [CMTime] = []
            let count = min(Int(duration * fps), 50) // Reduced from 200 to 50
            for i in 0..<count {
                let t = Double(i) / fps
                times.append(CMTime(seconds: t, preferredTimescale: 600))
            }

            var loadedImages: [NSImage] = []
            var loadedTimes: [Double] = []

            for await result in generator.images(for: times) {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                switch result {
                case .success(requestedTime: let req, image: let img, actualTime: _):
                    loadedImages.append(NSImage(cgImage: img, size: .zero))
                    loadedTimes.append(req.seconds)
                case .failure:
                    continue
                }
            }

            let finalImages = loadedImages
            let finalTimes = loadedTimes

            await MainActor.run {
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                self.timelineFrames = finalImages
                self.timelineFrameTimes = finalTimes
            }
        }
    }

    // MARK: -  Load Full-Res Frame
    func loadFullResolutionFrame(at timeSeconds: Double) {
        if videoAsset == nil, !timelineFrames.isEmpty {
             if let original = originalThumbnail {
                 self.installOriginal(original)
             }
             return
        }

        guard let asset = videoAsset else { return }

        frameTask?.cancel()
        let generation = UUID()
        frameGeneration = generation
        filterGeneration = UUID()
        frameTask = Task {
            let tracks = try? await asset.loadTracks(withMediaType: AVMediaType.video)
            guard let videoTrack = tracks?.first else { return }

            let naturalSize = try? await videoTrack.load(.naturalSize)
            let preferredTransform = try? await videoTrack.load(.preferredTransform)

            var videoSize = naturalSize ?? CGSize(width: 1920, height: 1080)

            if let t = preferredTransform,
               (t.a == 0 && t.b == 1 && t.c == -1 && t.d == 0) ||
               (t.a == 0 && t.b == -1 && t.c == 1 && t.d == 0) {
                videoSize = CGSize(width: videoSize.height, height: videoSize.width)
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = videoSize
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ns = NSImage(cgImage: cgImage, size: .zero)

                await MainActor.run {
                    guard generation == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(ns)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.frameGeneration, !Task.isCancelled else { return }
                    if self.selectedFrameIndex < self.timelineFrames.count {
                        let fallback = self.timelineFrames[self.selectedFrameIndex]
                        self.installOriginal(fallback)
                    }
                }
            }
        }
    }

}
