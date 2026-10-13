import AVFoundation
import Foundation

@main struct SourceVideoTimingRegression {
    static func main() async {
        do {
            let root = URL(fileURLWithPath: CommandLine.arguments[1])
            for (name, numerator, denominator, count) in [("fractional", Int64(24000), Int64(1001), Int64(48)), ("integer", 30, 1, 60)] {
                let result = try await SourceVideoTiming.inspect(url: root.appendingPathComponent("\(name).mp4"))
                precondition(result.isVerifiedCFR)
                precondition(result.frameCount == count && result.rateNumerator == numerator && result.rateDenominator == denominator)
                precondition(abs(result.duration.seconds - Double(count) * Double(denominator) / Double(numerator)) < 0.001)
            }
            let single = try await SourceVideoTiming.inspect(url: root.appendingPathComponent("single.mp4"))
            precondition(single.isVerifiedCFR && single.frameCount == 1 && single.rateNumerator != nil && single.rateDenominator != nil)
            let variable = try await SourceVideoTiming.inspect(url: root.appendingPathComponent("variable.mp4"))
            precondition(!variable.isVerifiedCFR && variable.rateNumerator == nil)
            let audioOnly = try await SourceVideoTiming.inspect(url: root.appendingPathComponent("audio.m4a"))
            precondition(!audioOnly.isVerifiedCFR && audioOnly.frameCount == nil && !audioOnly.duration.isValid)
            var checks = 0
            do {
                _ = try await SourceVideoTiming.inspect(url: root.appendingPathComponent("fractional.mp4"), checkCancellation: {
                    checks += 1
                    if checks >= 10 { throw CancellationError() }
                })
                fatalError("Cancellation ignored")
            } catch is CancellationError { }
            print("PASS metadata timing: 24000/1001, 30fps, B-frame display order, single-frame container rounding, video duration excluding longer audio, VFR rejection, no-video unknown, cursor-walk cancellation")
        } catch { fputs("FAIL timing: \(error)\n", stderr); exit(1) }
    }
}
