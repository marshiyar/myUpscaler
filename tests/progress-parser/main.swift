import Foundation

// The app's progress parser against the lines the Rust backend logs (backend/src/job.rs). The backend's
// end-to-end tests check that it writes lines of this form.

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

let header = ProgressParser.parse(line: "Input #0: /clips/a.mp4\n  Duration: 00:01:40.00, h264 1920x1080, 23.976 fps\n",
                                  currentDuration: 0)
require(header.newDuration == 100, "The Duration line sets the duration")
require(header.timeString == nil && header.progress == nil, "The Duration line is not progress")

let halfway = ProgressParser.parse(line: "frame=   2878 fps=14.20 time=00:00:50.00 speed=0.592x progress=50.0%\n",
                                   currentDuration: 100)
require(halfway.fps == "14.20", "fps is read")
require(halfway.timeString == "00:00:50.00", "time is read")
require(halfway.progress.map { abs($0 - 0.5) < 1e-9 } == true, "progress is time over duration")
require(halfway.eta == "1:24", "ETA is the remaining time at the current speed (50 s / 0.592)")

let done = ProgressParser.parse(line: "frame=   5755 fps=14.31 time=00:01:40.00 speed=0.597x progress=100.0%\n",
                                currentDuration: 100)
require(done.progress == 1.0 && done.eta == "0:00", "The last progress line completes the bar")

let other = ProgressParser.parse(line: "Filters: decimate(hi=768, lo=320, frac=0.33) -> lanczos(x2.00)\n",
                                 currentDuration: 100)
require(other.progress == nil && other.fps == nil, "Other log lines leave progress alone")
require(ProgressParser.formatTime(3725) == "1:02:05", "Hours are formatted")
print("10 progress parser checks passed")
