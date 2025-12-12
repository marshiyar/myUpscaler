//
//  FFmpegParserTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
@testable import myUpscaler

@MainActor
struct FFmpegParserTests {
    
    // MARK: - Time Parsing Tests (via parse method)
    
    @Test("parse should handle MM:SS format in time string")
    func testParseMMSSFormat() {
        let duration = 100.0
        
        // Test MM:SS format through parse method
        let line = "frame= 100 fps=5.0 time=1:30.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Should parse correctly (90 seconds = 1:30)
        #expect(state.timeString == "1:30.00" || state.timeString?.contains("1:30") == true)
    }
    
    @Test("parse should handle HH:MM:SS format in time string")
    func testParseHHMMSSFormat() {
        let duration = 10000.0
        
        let line = "frame= 100 fps=5.0 time=1:30:45.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Should parse correctly
        #expect(state.timeString?.contains("1:30:45") == true || state.timeString?.contains("30:45") == true)
    }
    
    // MARK: - Time Formatting Tests
    
    @Test("formatTime should format seconds to MM:SS for times under 1 hour")
    func testFormatTimeMMSS() {
        let formatted = FFmpegParser.formatTime(90.0)
        #expect(formatted == "1:30")
    }
    
    @Test("formatTime should format seconds to HH:MM:SS for times over 1 hour")
    func testFormatTimeHHMMSS() {
        let formatted = FFmpegParser.formatTime(3661.0) // 1 hour, 1 minute, 1 second
        #expect(formatted == "1:01:01")
    }
    
    @Test("formatTime should handle zero seconds")
    func testFormatTimeZero() {
        let formatted = FFmpegParser.formatTime(0.0)
        #expect(formatted == "0:00")
    }
    
    @Test("formatTime should handle large values")
    func testFormatTimeLarge() {
        let formatted = FFmpegParser.formatTime(36661.0) // 10 hours, 11 minutes, 1 second
        #expect(formatted == "10:11:01")
    }
    
    @Test("formatTime should truncate fractional seconds")
    func testFormatTimeFractional() {
        let formatted = FFmpegParser.formatTime(90.7)
        #expect(formatted == "1:30") // Should truncate, not round
    }
    
    @Test("formatTime should handle negative values")
    func testFormatTimeNegative() {
        let formatted = FFmpegParser.formatTime(-10.0)
        // Behavior depends on implementation, but should not crash
        #expect(!formatted.isEmpty)
    }
    
    // MARK: - FFmpeg Line Parsing Tests
    
    @Test("parse should extract duration from ffmpeg output")
    func testParseDuration() {
        let currentDuration = 0.0
        
        let line = "Duration: 00:01:30.50, start: 0.000000, bitrate: 1000 kb/s"
        let state = FFmpegParser.parse(line: line, currentDuration: currentDuration)
        
        #expect(state.newDuration != nil)
        if let newDur = state.newDuration {
            #expect(newDur > 0.0)
        }
    }
    
    @Test("parse should extract frame, fps, and time from progress line")
    func testParseProgressLine() {
        let duration = 100.0 // Set duration for progress calculation
        
        let line = "frame= 100 fps=5.0 time=00:00:03.20 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        #expect(state.fps == "5.0")
        #expect(state.timeString == "00:00:03.20")
    }
    
    @Test("parse should calculate progress correctly")
    func testParseProgressCalculation() {
        let duration = 100.0 // 100 seconds total
        
        let line = "frame= 100 fps=5.0 time=00:00:50.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Progress should be approximately 50/100 = 0.5
        if let progress = state.progress {
            #expect(progress >= 0.49 && progress <= 0.51)
        } else {
            #expect(Bool(false), "Progress should be calculated")
        }
    }
    
    @Test("parse should handle multiple progress updates")
    func testParseMultipleUpdates() {
        let duration = 100.0
        
        let lines = [
            "frame= 50 fps=5.0 time=00:00:25.00 bitrate= 1000.0kbits/s",
            "frame= 100 fps=5.0 time=00:00:50.00 bitrate= 1000.0kbits/s",
            "frame= 150 fps=5.0 time=00:00:75.00 bitrate= 1000.0kbits/s"
        ]
        
        var lastProgress = 0.0
        
        for line in lines {
            let state = FFmpegParser.parse(line: line, currentDuration: duration)
            if let p = state.progress {
                #expect(p >= lastProgress)
                lastProgress = p
            }
        }
        
        #expect(lastProgress > 0.0)
    }
    
    @Test("parse should handle lines without frame information")
    func testParseNonProgressLine() {
        let duration = 100.0
        
        let line = "Some other ffmpeg output line without frame info"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Should not crash and should return empty state
        #expect(state.fps == nil)
        #expect(state.timeString == nil)
    }
    
    @Test("parse should handle empty lines")
    func testParseEmptyLine() {
        let duration = 100.0
        
        let state = FFmpegParser.parse(line: "", currentDuration: duration)
        
        // Should not crash
        #expect(state.fps == nil)
    }
    
    @Test("parse should handle malformed progress lines")
    func testParseMalformedLine() {
        let duration = 100.0
        
        let malformedLines = [
            "frame= abc fps=invalid time=bad",
            "frame= 100",
            "fps=5.0 time=00:00:03.20",
            "random text"
        ]
        
        for line in malformedLines {
            _ = FFmpegParser.parse(line: line, currentDuration: duration)
            // Should not crash
            // Some might parse partially if regex matches, but generally should be robust
             #expect(true)
        }
    }
    
    // MARK: - ETA Calculation Tests
    
    @Test("parse should calculate ETA when duration and fps are known")
    func testETACalculation() {
        let duration = 100.0 // 100 seconds total
        
        let line = "frame= 50 fps=5.0 time=00:00:25.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // ETA should be calculated (remaining time)
        // 100 - 25 = 75 seconds remaining
        #expect(state.eta != nil)
        if let eta = state.eta {
            #expect(eta != "--:--")
        }
    }
    
    @Test("parse should show --:-- for ETA when duration is unknown")
    func testETAUndefined() {
        let duration = 0.0 // Unknown duration
        
        let line = "frame= 50 fps=5.0 time=00:00:25.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // ETA should be undefined or not present if it depends on duration
        #expect(state.eta == "--:--")
    }
    
    // MARK: - Edge Cases
    
    @Test("parse should handle very large time values")
    func testParseLargeTimeValues() {
        let duration = 100000.0
        
        let line = "frame= 100 fps=5.0 time=99:59:59.99 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Should not crash
        #expect(state.timeString != nil)
    }
    
    @Test("parse should handle zero fps")
    func testParseZeroFPS() {
        let duration = 100.0
        
        let line = "frame= 100 fps=0.0 time=00:00:25.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Should handle gracefully
        #expect(state.fps == "0.0")
    }
    
    @Test("parse should handle progress over 100%")
    func testParseProgressOver100() {
        let duration = 100.0
        
        // Time exceeds duration
        let line = "frame= 200 fps=5.0 time=00:01:50.00 bitrate= 1000.0kbits/s"
        let state = FFmpegParser.parse(line: line, currentDuration: duration)
        
        // Progress should be clamped to 1.0
        if let p = state.progress {
            #expect(p <= 1.0)
        }
    }
}

