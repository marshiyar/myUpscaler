import XCTest
@testable import myUpscaler

@MainActor class SecurityTests: XCTestCase {
    
    // Captured options for inspection
    var lastOptions: up60p_options?
    var processCalled = false
    var cancelCalled = false
    
    override func setUp() {
        super.setUp()
        // Reset state
        lastOptions = nil
        processCalled = false
        cancelCalled = false
        
        // Define a mock bridge
        let mockBridge = Up60PBridge(
            initFunc: { _, _ in UP60P_OK },
            defaultOptionsFunc: { opts in
                guard let opts = opts else { return }
                // Initialize with zeroes/defaults to avoid random garbage
                memset(opts, 0, MemoryLayout<up60p_options>.size)
            },
            processPathFunc: { [weak self] _, opts in
                self?.processCalled = true
                if let opts = opts {
                    self?.lastOptions = opts.pointee
                }
                
                // Simulate checking for cancellation
                if self?.cancelCalled == true {
                    return UP60P_ERR_INTERNAL // or some interruption code
                }
                return UP60P_OK
            },
            setDryRunFunc: { _ in },
            shutdownFunc: { },
            cancelFunc: { [weak self] in self?.cancelCalled = true }
        )
        
        Up60PEngine.useBridgeForTesting(mockBridge)
    }
    
    override func tearDown() {
        Up60PEngine.resetBridgeForTesting()
        super.tearDown()
    }
    
    // Helper to extract String from C char array
    func stringFromFixedBuffer<T>(_ tuple: T) -> String {
        return withUnsafeBytes(of: tuple) { bytes in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else { return "" }
            return String(cString: base)
        }
    }
    
    // MARK: - 1. Buffer Truncation Safety
    func testBufferTruncationSafety() async throws {
        let settings = UpscaleSettings()
        // 'codec' is char[8]. Try to pass a longer string.
        _ = "12345678901234567890"
        
        // `preset` is char[32]
        let longPreset = String(repeating: "A", count: 100)
        settings.preset = longPreset
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        
        let capturedPreset = stringFromFixedBuffer(opts.preset)
        
        // Should be truncated to fit 32 bytes (including null terminator, so 31 chars max)
        XCTAssertTrue(capturedPreset.count < 32, "Preset should be truncated")
        XCTAssertEqual(capturedPreset, String(longPreset.prefix(31)), "Should contain first 31 chars")
    }
    
    // MARK: - 2. Command Injection Vectors (x265_params)
    func testCommandInjectionVectors() async throws {
        let settings = UpscaleSettings()
        // x265Params is built from components. Let's inject into one.
        // x265AqMode is appended as "aq-mode=\(x265AqMode)"
        let injectionPayload = "1; rm -rf /; echo" 
        settings.x265AqMode = injectionPayload
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        let capturedParams = stringFromFixedBuffer(opts.x265_params)
        
        // Verify the injection payload made it through (the C engine must handle safety)
        XCTAssertTrue(capturedParams.contains(injectionPayload), "Injection payload should be present in params")
    }
    
    // MARK: - 3. Path Traversal
    func testPathTraversal() async throws {
        let settings = UpscaleSettings()
        let maliciousPath = "../../../../../etc/passwd"
        settings.lutPath = maliciousPath
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        let capturedLut = stringFromFixedBuffer(opts.lut3d_file)
        
        XCTAssertEqual(capturedLut, maliciousPath, "Path traversal string passed to engine")
    }
    
    // MARK: - 4. Null Byte Injection
    func testNullByteInjection() async throws {
        let settings = UpscaleSettings()
        // Swift strings can contain nulls. C strings terminate at the first null.
        let nullPayload = "veryfast\0malicious_command"
        settings.preset = nullPayload
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        let capturedPreset = stringFromFixedBuffer(opts.preset)
        
        // C string construction should stop at first null byte or handle it safely
        XCTAssertEqual(capturedPreset, "veryfast", "String should be truncated at null byte")
    }
    
    // MARK: - 5. Input Fuzzing (Basic)
    func testInputFuzzing() async throws {
        // Run multiple iterations with random garbage
        for i in 0..<10 {
            let settings = UpscaleSettings()
            settings.preset = randomString(length: 50)
            settings.fps = randomString(length: 10)
            settings.scaleFactor = Double.random(in: -1000...1000)
            settings.aiModelPath = randomString(length: 200)
            
            do {
                try await Up60PEngine.shared.process(inputPath: "/tmp/in_\(i).mp4", settings: settings, outputDirectory: "/tmp")
                XCTAssertTrue(processCalled)
            } catch {
                XCTFail("Fuzzing crashed or threw error: \(error)")
            }
        }
    }
    
    // MARK: - 6. Unicode Safety
    func testUnicodeHandling() async throws {
        let settings = UpscaleSettings()
        let unicodeString = "🚀🥺über"
        settings.preset = unicodeString
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        let capturedPreset = stringFromFixedBuffer(opts.preset)
        
        XCTAssertEqual(capturedPreset, unicodeString)
    }
    
    // MARK: - 7. Empty Strings
    func testEmptyStrings() async throws {
        let settings = UpscaleSettings()
        settings.preset = ""
        settings.aiModelPath = ""
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.preset), "")
        XCTAssertEqual(stringFromFixedBuffer(opts.ai_model), "")
    }
    
    // MARK: - 8. Large Numeric Values
    func testLargeNumericValues() async throws {
        let settings = UpscaleSettings()
        settings.scaleFactor = 1.0e10 // Huge number
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        let capturedScale = stringFromFixedBuffer(opts.scale_factor)
        XCTAssertFalse(capturedScale.isEmpty)
    }
    
    // MARK: - 9. Boundary Conditions
    func testBoundaryConditions() async throws {
        let settings = UpscaleSettings()
        // preset is 32 chars. Max string len is 31.
        let boundaryString = String(repeating: "B", count: 31)
        settings.preset = boundaryString
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.preset), boundaryString)
    }
    
    // MARK: - 10. Format String Injection
    func testFormatStringInjection() async throws {
        let settings = UpscaleSettings()
        let fmtPayload = "%s%s%s%s"
        settings.preset = fmtPayload
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.preset), fmtPayload)
    }
    
    // MARK: - 11. Symlink Attack
    func testSymlinkAttack() async throws {
        // Test that symbolic links in paths are passed through
        // (The engine should probably check these, but we test the bridging)
        let settings = UpscaleSettings()
        let symlinkPath = "/tmp/mysymlink"
        settings.aiModelPath = symlinkPath
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.ai_model), symlinkPath)
    }
    
    // MARK: - 12. Output Directory Traversal
    func testOutputDirectoryTraversal() async throws {
        let settings = UpscaleSettings()
        let outDir = "/tmp/../../../etc"
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: outDir)
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.outdir), outDir)
    }
    
    // MARK: - 13. Excessive Threads
    func testExcessiveThreads() async throws {
        let settings = UpscaleSettings()
        settings.threads = "99999999"
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        XCTAssertEqual(stringFromFixedBuffer(opts.threads), "99999999")
    }
    
    // MARK: - 14. Environment Variable Injection
    func testEnvironmentVariableInjection() async throws {
        let settings = UpscaleSettings()
        let envPayload = "$HOME/malicious"
        settings.aiModelPath = envPayload
        
        try await Up60PEngine.shared.process(inputPath: "/tmp/in.mp4", settings: settings, outputDirectory: "/tmp")
        
        guard let opts = lastOptions else { XCTFail("Options not captured"); return }
        // Swift string doesn't expand, so it should be passed as is.
        XCTAssertEqual(stringFromFixedBuffer(opts.ai_model), envPayload)
    }

    // MARK: - 15. Verify Safe Defaults
    func testSafeDefaults() async throws {
        let settings = UpscaleSettings()
        // Ensure default settings don't have risky values
        XCTAssertFalse(settings.aiModelPath.contains(".."))
        XCTAssertEqual(settings.threads, "0")
    }

    // MARK: - Helpers
    
    func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
}
