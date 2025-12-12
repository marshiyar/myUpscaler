//
//  TestAssets.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Foundation

/// Defines synthetic test assets and scenarios for testing
struct TestAssets {
    
    struct VideoScenario {
        let name: String
        let description: String
        let recommendedSettings: [String: String]
        let expectedDifficulty: String
        let resolution: String
        let duration: String
    }
    
    static let scenarios: [VideoScenario] = [
        VideoScenario(
            name: "Clean Daylight",
            description: "High quality footage with good lighting. Minimal noise.",
            recommendedSettings: ["denoiser": "none", "sharpen": "cas", "scale": "2.0"],
            expectedDifficulty: "Low",
            resolution: "1920x1080",
            duration: "00:00:30"
        ),
        VideoScenario(
            name: "Low Light Noisy",
            description: "Dark footage with heavy sensor noise and grain.",
            recommendedSettings: ["denoiser": "nlmeans", "strength": "5.0", "deblock": "strong"],
            expectedDifficulty: "High",
            resolution: "1280x720",
            duration: "00:00:45"
        ),
        VideoScenario(
            name: "Anime / Cartoon",
            description: "Flat colors, sharp edges, distinct from live action.",
            recommendedSettings: ["model": "RealESRGAN_Anime", "scale": "4.0"],
            expectedDifficulty: "Medium",
            resolution: "1920x1080",
            duration: "00:01:00"
        ),
        VideoScenario(
            name: "Sports Action",
            description: "Fast motion with potential blurring and compression artifacts.",
            recommendedSettings: ["fps": "60", "interpolation": "mci"],
            expectedDifficulty: "High",
            resolution: "1280x720",
            duration: "00:00:20"
        ),
        VideoScenario(
            name: "Shaky Handheld",
            description: "Unstable camera movement, testing motion estimation.",
            recommendedSettings: ["stabilize": "true (future)", "interpolation": "blend"],
            expectedDifficulty: "Medium",
            resolution: "3840x2160",
            duration: "00:00:15"
        ),
        VideoScenario(
            name: "Old Phone Footage",
            description: "Low bitrate, blocky artifacts, oversaturated.",
            recommendedSettings: ["deblock": "strong", "denoiser": "hqdn3d"],
            expectedDifficulty: "Very High",
            resolution: "640x480",
            duration: "00:02:00"
        ),
        VideoScenario(
            name: "Web Compression",
            description: "Heavily compressed video with macroblocking.",
            recommendedSettings: ["deblock": "strong", "deband": "f3kdb"],
            expectedDifficulty: "High",
            resolution: "1280x720",
            duration: "00:05:00"
        )
    ]
    
    /// Returns a list of file names representing these scenarios (mock files)
    static func generateMockFiles() -> [String] {
        return scenarios.map { scenario in
            let safeName = scenario.name.replacingOccurrences(of: " ", with: "_").lowercased()
            return "\(safeName).mp4"
        }
    }
}

