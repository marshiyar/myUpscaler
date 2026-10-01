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
                let (cgImage, actualTime) = try await imageGenerator.image(at: time)
                let nsImage = NSImage(cgImage: cgImage, size: .zero)

                await MainActor.run {
                    guard generation == self.mediaGeneration, selectedFrame == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(nsImage, presentationTime: actualTime)
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
                self.timelinePresentationTimes = []
                return
            }
        }

        let asset = AVURLAsset(url: url)
        videoAsset = asset

        let generation = mediaGeneration
        timelineTask?.cancel()
        let loader = VideoTimelineLoader()
        timelineTask = Task {
            do {
                let result = try await loader.load(url: url)
                guard generation == self.mediaGeneration, !Task.isCancelled else { return }
                self.videoFPS = result.fps
                self.totalFrames = result.estimatedTotalFrames
                self.timelineFrames = result.samples.map { NSImage(cgImage: $0.image, size: .zero) }
                self.timelinePresentationTimes = result.samples.map(\.presentationTime)
                self.timelineFrameTimes = result.samples.map { $0.presentationTime.seconds }
                if result.failedRequests > 0 {
                    print("Timeline: \(result.failedRequests) requests could not produce a nearby frame.")
                }
            } catch is CancellationError { }
            catch { print("Timeline error: \(error)") }
        }
    }

    // MARK: -  Load Full-Res Frame
    func loadFullResolutionFrame(at timeSeconds: Double, presentationTime: CMTime? = nil) {
        if videoAsset == nil, !timelineFrames.isEmpty {
             if let original = originalThumbnail {
                 self.installOriginal(original)
             }
             return
        }

        guard let asset = videoAsset else { return }

        let time = presentationTime ?? CMTime(seconds: timeSeconds, preferredTimescale: 600)
        if pendingFramePresentationTime == time { return }
        if loadedFramePresentationTime == time, originalThumbnail != nil { return }
        frameTask?.cancel()
        let generation = beginFrameRequest()
        pendingFramePresentationTime = time
        frameTask = Task {
            defer {
                if self.frameGeneration == generation { self.pendingFramePresentationTime = nil }
            }
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

            do {
                let (cgImage, _) = try await generator.image(at: time)
                let ns = NSImage(cgImage: cgImage, size: .zero)

                await MainActor.run {
                    guard generation == self.frameGeneration, !Task.isCancelled else { return }
                    self.installOriginal(ns, presentationTime: time)
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
