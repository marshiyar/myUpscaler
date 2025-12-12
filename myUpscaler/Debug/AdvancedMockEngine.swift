import Foundation

#if DEBUG

class AdvancedMockEngine: EngineProtocol {
    
    enum Behavior {
        case success
        case error(Error)
        case crash // Simulate a crash/hang
        case timeout
    }
    
    // Configuration
    var behavior: Behavior = .success
    var processingDelay: TimeInterval = 0.01
    
    // Inspection
    private(set) var lastCapturedSettings: UpscaleSettings?
    private(set) var lastInputPath: String?
    private(set) var lastOutputPath: String?
    private(set) var processCallCount = 0
    private(set) var cancelCallCount = 0
    
    // Log simulation
    var logHandler: ((String) -> Void)?
    var simulatedLogs: [String] = []
    
    func setLogHandler(_ handler: @escaping (String) -> Void) {
        self.logHandler = handler
    }
    
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        processCallCount += 1
        lastInputPath = inputPath
        lastOutputPath = outputDirectory
        
        self.lastCapturedSettings = settings
        
        if processingDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(processingDelay * 1_000_000_000))
        }
        
        switch behavior {
        case .success:
            simulateLogOutput()
        case .error(let error):
            throw error
        case .crash:
            throw NSError(domain: "com.myupscaler.test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Simulated Crash"])
        case .timeout:
            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
        }
    }
    
    func cancel() {
        cancelCallCount += 1
    }
    
    private func simulateLogOutput() {
        guard let handler = logHandler else { return }
        
        if simulatedLogs.isEmpty {
            handler("Duration: 00:00:10.00, start: 0.000000, bitrate: 1000 kb/s")
            
            for i in 0...10 {
                let time = Double(i)
                handler("frame= \(i*60) fps=60.0 time=\(String(format: "00:00:%02.2f", time)) bitrate= 1000.0kbits/s speed= 1.0x")
            }
            handler("video:1000kB audio:100kB subtitle:0kB other streams:0kB global headers:0kB muxing overhead: 1.000%")
            handler("elapsed=10.0s")
            handler("Done.")
        } else {
            for log in simulatedLogs {
                handler(log)
            }
        }
    }
}

#endif

