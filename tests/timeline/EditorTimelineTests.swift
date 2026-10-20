import AppKit
import AVFoundation
@main struct EditorTimelineTests {
 @MainActor static func main() async throws {
  let state=EditorState()
  let first=CommandLine.arguments[1], next=CommandLine.arguments[2]
  state.filePath=first
  let old=state.timelineTask
  state.filePath=next
  await old?.value
  await state.timelineTask?.value
  precondition(state.filePath==next)
  precondition(state.timelineFrames.count==50 && state.timelinePresentationTimes.count==50)
  state.selectFrame(11)
  let requestGeneration=state.frameGeneration
  state.selectFrame(11)
  precondition(state.frameGeneration==requestGeneration,"Duplicate pending selection decoded again")
  await state.frameTask?.value
  precondition(state.originalThumbnail != nil)
  precondition(state.loadedFramePresentationTime == state.timelinePresentationTimes[11])
  let loadedGeneration=state.frameGeneration
  state.selectFrame(11)
  precondition(state.frameGeneration==loadedGeneration,"Duplicate loaded selection decoded again")
  state.filePath=first
  precondition(state.loadedFramePresentationTime==nil && state.pendingFramePresentationTime==nil)
  await state.timelineTask?.value
  print("PASS newest import publication, actual CMTime selection, pending/loaded request deduplication, cache reset")
 }
}
