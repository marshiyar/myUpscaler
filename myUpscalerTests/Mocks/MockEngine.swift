import Foundation
@testable import myUpscaler

class MockEngine: EngineProtocol {
    
    var logHandler: ((String) -> Void)?
    
    var processCalled = false
    var cancelCalled = false
    
    var processInputPath: String?
    var processSettings: UpscaleSettings?
    var processOutputPath: String?
    
    var simulateError: Error?
    var simulateDelay: TimeInterval = 0
    var simulateLogOutput: [String] = []
    
    func setLogHandler(_ handler: @escaping (String) -> Void) {
        self.logHandler = handler
    }
    
    func process(inputPath: String, settings: UpscaleSettings, outputDirectory: String) async throws {
        processCalled = true
        processInputPath = inputPath
        processSettings = settings
        processOutputPath = outputDirectory
        
        if simulateDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(simulateDelay * 1_000_000_000))
        }
        
        // Simulate logs
        for log in simulateLogOutput {
            if Task.isCancelled { break }
            logHandler?(log)
            // Small yield to simulate async nature
            await Task.yield()
        }
        
        if let error = simulateError {
            throw error
        }
        
        if Task.isCancelled {
            throw CancellationError()
        }
    }
    
    func cancel() {
        cancelCalled = true
    }
}

