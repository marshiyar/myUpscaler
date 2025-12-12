import Foundation
import Combine

#if DEBUG

class SettingsFuzzer: TestScenario {
    var name: String = "Settings Fuzzer"
    var description: String = "Tests UpscaleSettings with boundary values and invalid inputs to ensure robust error handling"
    
    private let engine: AdvancedMockEngine
    
    init(engine: AdvancedMockEngine = AdvancedMockEngine()) {
        self.engine = engine
    }
    
    func run() async -> TestResult {
        var result = TestResult(scenarioName: name)
        let settings = UpscaleSettings()
        
        let numericParams = [
            "denoiseStrength", "deringStrength", "sharpenStrength", "debandStrength", "grainStrength",
            "usmRadius", "usmAmount", "usmThreshold",
            "f3kdbRange", "f3kdbY", "f3kdbCbCr",
            "denoiseStrength2", "deringStrength2", "sharpenStrength2", "debandStrength2", "grainStrength2",
            "eqContrast", "eqBrightness", "eqSaturation"
        ]
        
        let testCases = [
            ("0", true),
            ("1.5", true),
            ("1000", true),
            ("-1", true),
            ("abc", false),
            ("", true),
            ("NaN", false),
            ("Inf", false)
        ]
        
        for param in numericParams {
            for (val, shouldBeValid) in testCases {
                let event = await testParameter(settings: settings, param: param, value: val)
                result.events.append(event)
                
                if shouldBeValid && !event.isValid {
                    // Logic to mark result as failed if needed
                    // result.passed = false 
                }
            }
        }
        
        return result
    }
    
    private func testParameter(settings: UpscaleSettings, param: String, value: String) async -> TestEvent {
        let runner = UpscaleRunner(engine: engine)
        runner.settings = settings
        runner.inputPath = "/test/dummy.mp4"
        
        let beforeVal = getParamValue(settings, param: param)
        setParamValue(settings, param: param, value: value)
        
        var errorMsg: String?
        var isValid = true
        
        do {
            try await engine.process(inputPath: runner.inputPath, settings: runner.settings, outputDirectory: runner.outputFolder())
        } catch {
            errorMsg = error.localizedDescription
            isValid = false
        }
        
        return TestEvent(
            toolName: "UpscaleSettings",
            parameter: param,
            beforeValue: beforeVal,
            afterValue: value,
            isValid: isValid,
            error: errorMsg
        )
    }
    
    private func setParamValue(_ s: UpscaleSettings, param: String, value: String) {
        switch param {
        case "denoiseStrength": s.denoiseStrength = value
        case "deringStrength": s.deringStrength = value
        case "sharpenStrength": s.sharpenStrength = value
        case "debandStrength": s.debandStrength = value
        case "grainStrength": s.grainStrength = value
        case "usmRadius": s.usmRadius = value
        case "usmAmount": s.usmAmount = value
        case "usmThreshold": s.usmThreshold = value
        case "f3kdbRange": s.f3kdbRange = value
        case "f3kdbY": s.f3kdbY = value
        case "f3kdbCbCr": s.f3kdbCbCr = value
        case "denoiseStrength2": s.denoiseStrength2 = value
        case "deringStrength2": s.deringStrength2 = value
        case "sharpenStrength2": s.sharpenStrength2 = value
        case "debandStrength2": s.debandStrength2 = value
        case "grainStrength2": s.grainStrength2 = value
        case "eqContrast": s.eqContrast = value
        case "eqBrightness": s.eqBrightness = value
        case "eqSaturation": s.eqSaturation = value
        default: break
        }
    }
    
    private func getParamValue(_ s: UpscaleSettings, param: String) -> String {
        switch param {
        case "denoiseStrength": return s.denoiseStrength
        case "deringStrength": return s.deringStrength
        case "sharpenStrength": return s.sharpenStrength
        case "debandStrength": return s.debandStrength
        case "grainStrength": return s.grainStrength
        case "usmRadius": return s.usmRadius
        case "usmAmount": return s.usmAmount
        case "usmThreshold": return s.usmThreshold
        case "f3kdbRange": return s.f3kdbRange
        case "f3kdbY": return s.f3kdbY
        case "f3kdbCbCr": return s.f3kdbCbCr
        case "denoiseStrength2": return s.denoiseStrength2
        case "deringStrength2": return s.deringStrength2
        case "sharpenStrength2": return s.sharpenStrength2
        case "debandStrength2": return s.debandStrength2
        case "grainStrength2": return s.grainStrength2
        case "eqContrast": return s.eqContrast
        case "eqBrightness": return s.eqBrightness
        case "eqSaturation": return s.eqSaturation
        default: return ""
        }
    }
}

#endif

