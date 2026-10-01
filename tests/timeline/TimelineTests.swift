import AVFoundation
import Foundation
@main struct TimelineTests {
 nonisolated static func pixels(_ image:CGImage) -> Data {
  var bytes=Data(count:image.width*image.height*4)
  bytes.withUnsafeMutableBytes { raw in
   let context=CGContext(data:raw.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
   context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
  }
  return bytes
 }
 @MainActor static func main() async throws {
  let url=URL(fileURLWithPath:CommandLine.arguments[1])
  let loader=VideoTimelineLoader()
  let started=ProcessInfo.processInfo.systemUptime
  let result=try await loader.load(url:url)
  precondition(!result.samples.isEmpty && result.samples.count <= 50)
  precondition(result.failedRequests == 0, "Valid precise samples must not be dropped")
  let asset=AVURLAsset(url:url)
  let generator=AVAssetImageGenerator(asset:asset)
  generator.requestedTimeToleranceBefore = .zero
  generator.requestedTimeToleranceAfter = .zero
  generator.maximumSize=CGSize(width:200,height:200)
  let selected=result.samples[min(11,result.samples.count-1)]
  let (selectedImage,actual)=try await generator.image(at:selected.presentationTime)
  precondition(CMTimeCompare(actual,selected.presentationTime)==0)
  precondition(pixels(selectedImage) == pixels(selected.image), "Thumbnail and selected frame differ")
  precondition(Set(result.samples.map { $0.presentationTime.seconds }).count == result.samples.count)
  for sample in result.samples { precondition(sample.image.width<=200 && sample.image.height<=200) }
  print("PASS precise timeline count=\(result.samples.count), fractional/VFR presentation times, selected frame exact match; seconds=\(ProcessInfo.processInfo.systemUptime-started)")
  let task=Task { try await VideoTimelineLoader().load(url:url) }
  task.cancel()
  do { _ = try await task.value; preconditionFailure("Cancelled timeline accepted") } catch is CancellationError { }
  print("PASS pre-cancelled request rejects publication")
  let previous=VideoTimelineLoader()
  let old=Task { try await previous.load(url:url) }
  await Task.yield()
  old.cancel()
  let replacement=try await VideoTimelineLoader().load(url:url)
  do { _ = try await old.value; preconditionFailure("Cancelled previous import accepted") } catch is CancellationError { }
  precondition(replacement.samples.count == result.samples.count)
  print("PASS cancelled import and replacement decoder ownership")
 }
}
