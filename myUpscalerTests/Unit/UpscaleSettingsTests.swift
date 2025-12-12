//
//  UpscaleSettingsTests.swift
//  myUpscalerTests
//
//  Created by Test Suite
//

import Testing
import Foundation
@testable import myUpscaler

@MainActor struct UpscaleSettingsTests {
    
    // MARK: - Initialization Tests
    
    @Test("Default settings should have correct initial values")
    func testDefaultSettings() {
        let settings = UpscaleSettings()
        
        #expect(settings.useHEVC == false)
        #expect(settings.crf == 16.0)
        #expect(settings.preset == "slow")
        #expect(settings.fps == "60")
        #expect(settings.scaleFactor == 2.0)
        #expect(settings.scaler == "lanczos")
        #expect(settings.denoiser == "bm3d")
        #expect(settings.sharpenMethod == "cas")
        #expect(settings.debandMethod == "deband")
    }
    
    @Test("Metal pipeline defaults are sane")
    func testMetalPipelineDefaults() {
        let settings = UpscaleSettings()
        #expect(settings.enableColorLinearize == true)
        #expect(settings.encodeToSRGB == true)
        #expect(settings.useCosineFeather == true)
        #expect(settings.useTemporalSmoothing == false)
        #expect(settings.gammaBlendWeightValue == 0.0)
        #expect(settings.temporalStrengthValue == 0.15)
        #expect(settings.tileFeatherMarginValue == 0)
    }
    
    // MARK: - Auto-Toggle Tests (First Set)
    
    @Test("Setting deringStrength to 0 should disable deringActive")
    func testDeringStrengthAutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.deringActive = true
        settings.deringStrength = "1.0"
        
        // Wait for Combine publisher to process
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        #expect(settings.deringActive == true)
        
        settings.deringStrength = "0"
        
        // Wait for Combine publisher to process
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(settings.deringActive == false)
    }
    
    @Test("Enabling deringActive with strength 0 should restore a safe default")
    func testDeringActiveRestoresDefaultOnEnable() async throws {
        let settings = UpscaleSettings()
        settings.deringStrength = "0"
        settings.deringActive = false
        
        // Wait for Combine publisher to process
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.deringActive = true
        
        // Wait for Combine publisher to process
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(settings.deringActive == true)
        #expect(Double(settings.deringStrength) ?? 0 > 0)
    }
    
    // MARK: - Auto-Toggle Tests (Second Set)
    
    @Test("Setting denoiseStrength2 to 0 should disable useDenoise2")
    func testDenoiseStrength2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useDenoise2 = true
        settings.denoiseStrength2 = "2.5"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDenoise2 == true)
        
        settings.denoiseStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDenoise2 == false)
    }
    
    @Test("Setting deblockThresh2 to empty or 0 should disable useDeblock2")
    func testDeblockThresh2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useDeblock2 = true
        settings.deblockThresh2 = "10"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeblock2 == true)
        
        settings.deblockThresh2 = ""
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeblock2 == false)
        
        settings.deblockThresh2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeblock2 == false)
    }
    
    @Test("Setting deringStrength2 to 0 should disable useDering2 and deringActive2")
    func testDeringStrength2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useDering2 = true
        settings.deringActive2 = true
        settings.deringStrength2 = "0.5"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDering2 == true)
        #expect(settings.deringActive2 == true)
        
        settings.deringStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDering2 == false)
        #expect(settings.deringActive2 == false)
    }
    
    @Test("Setting sharpenStrength2 to 0 should disable useSharpen2 for CAS method")
    func testSharpenStrength2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useSharpen2 = true
        settings.sharpenMethod2 = "cas"
        settings.sharpenStrength2 = "0.25"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == true)
        
        settings.sharpenStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == false)
    }
    
    @Test("Setting all unsharp params to 0 should disable useSharpen2 for unsharp method")
    func testUnsharpParamsAutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useSharpen2 = true
        settings.sharpenMethod2 = "unsharp"
        settings.usmRadius2 = "5"
        settings.usmAmount2 = "1.0"
        settings.usmThreshold2 = "0.03"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == true)
        
        settings.usmRadius2 = "0"
        settings.usmAmount2 = "0"
        settings.usmThreshold2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == false)
    }
    
    @Test("Setting debandStrength2 to 0 should disable useDeband2 for non-f3kdb method")
    func testDebandStrength2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useDeband2 = true
        settings.debandMethod2 = "deband"
        settings.debandStrength2 = "0.015"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == true)
        
        settings.debandStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == false)
    }
    
    @Test("Setting all f3kdb params to 0 should disable useDeband2 for f3kdb method")
    func testF3kdbParamsAutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useDeband2 = true
        settings.debandMethod2 = "f3kdb"
        settings.f3kdbRange2 = "15"
        settings.f3kdbY2 = "64"
        settings.f3kdbCbCr2 = "64"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == true)
        
        settings.f3kdbRange2 = "0"
        settings.f3kdbY2 = "0"
        settings.f3kdbCbCr2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == false)
    }
    
    @Test("Setting grainStrength2 to 0 should disable useGrain2")
    func testGrainStrength2AutoToggle() async throws {
        let settings = UpscaleSettings()
        settings.useGrain2 = true
        settings.grainStrength2 = "1.0"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useGrain2 == true)
        
        settings.grainStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useGrain2 == false)
    }

    @Test("Re-enabling useDenoise2 at 0 should seed a default value instead of closing")
    func testDenoise2ReenableSeedsDefault() async throws {
        let settings = UpscaleSettings()
        settings.denoiseStrength2 = "0"
        settings.useDenoise2 = false
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useDenoise2 = true
        
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDenoise2 == true)
        #expect(Double(settings.denoiseStrength2) ?? 0 > 0)
    }

    @Test("Re-enabling useDering2 with zero strength should seed defaults")
    func testDering2ReenableSeedsDefault() async throws {
        let settings = UpscaleSettings()
        settings.useDering2 = false
        settings.deringActive2 = false
        settings.deringStrength2 = "0"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useDering2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(settings.useDering2 == true)
        #expect(Double(settings.deringStrength2) ?? 0 > 0)
    }
    
    @Test("Re-enabling useSharpen2 with zero params should repopulate defaults")
    func testSharpen2ReenableSeedsDefaults() async throws {
        let settings = UpscaleSettings()
        
        // CAS branch
        settings.useSharpen2 = false
        settings.sharpenMethod2 = "cas"
        settings.sharpenStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useSharpen2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == true)
        #expect(Double(settings.sharpenStrength2) ?? 0 > 0)
        
        // Unsharp branch
        settings.useSharpen2 = false
        settings.sharpenMethod2 = "unsharp"
        settings.usmRadius2 = "0"
        settings.usmAmount2 = "0"
        settings.usmThreshold2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useSharpen2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useSharpen2 == true)
        #expect(Double(settings.usmRadius2) ?? 0 > 0)
        #expect(Double(settings.usmAmount2) ?? 0 > 0)
        #expect(Double(settings.usmThreshold2) ?? 0 > 0)
    }
    
    @Test("Re-enabling useDeband2 with zero values should repopulate defaults")
    func testDeband2ReenableSeedsDefaults() async throws {
        let settings = UpscaleSettings()
        
        // Non-f3kdb branch
        settings.useDeband2 = false
        settings.debandMethod2 = "deband"
        settings.debandStrength2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useDeband2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == true)
        #expect(Double(settings.debandStrength2) ?? 0 > 0)
        
        // f3kdb branch
        settings.useDeband2 = false
        settings.debandMethod2 = "f3kdb"
        settings.f3kdbRange2 = "0"
        settings.f3kdbY2 = "0"
        settings.f3kdbCbCr2 = "0"
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useDeband2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDeband2 == true)
        #expect(Double(settings.f3kdbRange2) ?? 0 > 0)
        #expect(Double(settings.f3kdbY2) ?? 0 > 0)
        #expect(Double(settings.f3kdbCbCr2) ?? 0 > 0)
    }
    
    @Test("Re-enabling useGrain2 with zero strength should repopulate defaults")
    func testGrain2ReenableSeedsDefault() async throws {
        let settings = UpscaleSettings()
        settings.useGrain2 = false
        settings.grainStrength2 = "0"
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        settings.useGrain2 = true
        try await Task.sleep(nanoseconds: 100_000_000)
        
        #expect(settings.useGrain2 == true)
        #expect(Double(settings.grainStrength2) ?? 0 > 0)
    }
    
    // MARK: - x265Params Tests
    
    @Test("x265Params should build correct string from individual values")
    func testX265ParamsBuilding() {
        let settings = UpscaleSettings()
        settings.x265AqMode = "3"
        settings.x265PsyRd = "2.0"
        settings.x265Deblock1 = "-2"
        settings.x265Deblock2 = "-2"
        
        let params = settings.x265Params
        #expect(params.contains("aq-mode=3"))
        #expect(params.contains("psy-rd=2.0"))
        #expect(params.contains("deblock=-2,-2"))
    }
    
    @Test("x265Params should handle empty values correctly")
    func testX265ParamsEmptyValues() {
        let settings = UpscaleSettings()
        settings.x265AqMode = ""
        settings.x265PsyRd = "2.0"
        settings.x265Deblock1 = ""
        settings.x265Deblock2 = ""
        
        let params = settings.x265Params
        #expect(!params.contains("aq-mode="))
        #expect(params.contains("psy-rd=2.0"))
        #expect(!params.contains("deblock="))
    }
    
    @Test("parseX265Params should correctly parse comma-separated values")
    func testParseX265ParamsCommaSeparated() {
        let settings = UpscaleSettings()
        let paramsString = "aq-mode=3,psy-rd=2.0,deblock=-2,-2"
        
        settings.parseX265Params(from: paramsString)
        
        #expect(settings.x265AqMode == "3")
        #expect(settings.x265PsyRd == "2.0")
        #expect(settings.x265Deblock1 == "-2")
        #expect(settings.x265Deblock2 == "-2")
    }
    
    @Test("parseX265Params should correctly parse colon-separated values")
    func testParseX265ParamsColonSeparated() {
        let settings = UpscaleSettings()
        let paramsString = "aq-mode=3:psy-rd=2.0:deblock=-2,-2"
        
        settings.parseX265Params(from: paramsString)
        
        #expect(settings.x265AqMode == "3")
        #expect(settings.x265PsyRd == "2.0")
        #expect(settings.x265Deblock1 == "-2")
        #expect(settings.x265Deblock2 == "-2")
    }
    
    @Test("parseX265Params should use defaults for missing values")
    func testParseX265ParamsDefaults() {
        let settings = UpscaleSettings()
        let paramsString = "invalid=value"
        
        settings.parseX265Params(from: paramsString)
        
        // Should fall back to defaults
        #expect(settings.x265AqMode == "3")
        #expect(settings.x265PsyRd == "2.0")
        #expect(settings.x265Deblock1 == "-2")
        #expect(settings.x265Deblock2 == "-2")
    }
    
    @Test("x265Params should preserve comma in deblock parameter value")
    func testX265ParamsDeblockCommaPreservation() {
        let settings = UpscaleSettings()
        settings.x265AqMode = "3"
        settings.x265PsyRd = "2.0"
        settings.x265Deblock1 = "-2"
        settings.x265Deblock2 = "-2"
        
        let params = settings.x265Params
        
        // The deblock parameter should have a comma between its two values
        // Format: "deblock=-2,-2"
        #expect(params.contains("deblock=-2,-2"))
        
        // The comma in deblock should NOT be at a parameter boundary
        // (i.e., it should be within the deblock value, not separating parameters)
        let deblockRange = params.range(of: "deblock=")
        if let range = deblockRange {
            let afterDeblock = String(params[range.upperBound...])
            // Should contain comma before the next parameter or end
            #expect(afterDeblock.contains(",-2") || afterDeblock.hasPrefix("-2,-2"))
        }
    }
    
    @Test("x265Params should correctly format all parameters with deblock")
    func testX265ParamsCompleteFormat() {
        let settings = UpscaleSettings()
        settings.x265AqMode = "3"
        settings.x265PsyRd = "2.0"
        settings.x265Deblock1 = "-2"
        settings.x265Deblock2 = "-2"
        
        let params = settings.x265Params
        
        // Should contain all parameters
        #expect(params.contains("aq-mode=3"))
        #expect(params.contains("psy-rd=2.0"))
        #expect(params.contains("deblock=-2,-2"))
        
        // Parameters should be separated by commas (which will be converted to colons by C code)
        // But the comma within deblock should remain
        _ = params.split(separator: ",")
        // Should have 3 components: aq-mode=3, psy-rd=2.0, deblock=-2,-2
        // But deblock=-2,-2 will be split, so we need to check differently
        #expect(params.contains("aq-mode=3"))
        #expect(params.contains("psy-rd=2.0"))
        #expect(params.contains("deblock=-2,-2"))
    }
    
    // MARK: - Helper Method Tests
    
    @Test("isZero should correctly identify zero values")
    func testIsZero() {
        let settings = UpscaleSettings()
        
        #expect(settings.isZero("0") == true)
        #expect(settings.isZero("0.0") == true)
        #expect(settings.isZero("0.00") == true)
        #expect(settings.isZero("1") == false)
        #expect(settings.isZero("0.5") == false)
        #expect(settings.isZero("") == false)
        #expect(settings.isZero("invalid") == false)
    }
    
    @Test("isZeroOrEmpty should correctly identify zero or empty values")
    func testIsZeroOrEmpty() {
        let settings = UpscaleSettings()
        
        #expect(settings.isZeroOrEmpty("0") == true)
        #expect(settings.isZeroOrEmpty("") == true)
        #expect(settings.isZeroOrEmpty("0.0") == true)
        #expect(settings.isZeroOrEmpty("1") == false)
        #expect(settings.isZeroOrEmpty("0.5") == false)
    }
    
    // MARK: - Edge Cases
    
    @Test("Settings should handle invalid numeric strings gracefully")
    func testInvalidNumericStrings() async throws {
        let settings = UpscaleSettings()
        settings.useDenoise2 = true
        settings.denoiseStrength2 = "invalid"
        
        // Should not crash, but value won't be recognized as 0
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(settings.useDenoise2 == true) // Should remain true since "invalid" != 0
    }
    
    @Test("Settings should handle very large numeric values")
    func testLargeNumericValues() {
        let settings = UpscaleSettings()
        settings.denoiseStrength = "999999.99"
        settings.scaleFactor = 100.0
        
        #expect(settings.denoiseStrength == "999999.99")
        #expect(settings.scaleFactor == 100.0)
    }
    
    @Test("Settings should handle negative values")
    func testNegativeValues() {
        let settings = UpscaleSettings()
        settings.crf = -10.0
        settings.x265Deblock1 = "-2"
        
        #expect(settings.crf == -10.0)
        #expect(settings.x265Deblock1 == "-2")
    }
    
    // MARK: - Constants Tests
    
    @Test("Settings should have valid preset options")
    func testPresetOptions() {
        let settings = UpscaleSettings()
        
        #expect(settings.presets.contains("veryfast"))
        #expect(settings.presets.contains("slow"))
        #expect(settings.presets.contains("veryslow"))
        #expect(settings.presets.count == 6)
    }
    
    @Test("Settings should have valid scaler options")
    func testScalerOptions() {
        let settings = UpscaleSettings()
        
        #expect(settings.scalers.contains("ai"))
        #expect(settings.scalers.contains("lanczos"))
        #expect(settings.scalers.contains("zscale"))
        #expect(settings.scalers.contains("hw"))
    }
    
    @Test("Settings should have valid denoiser options")
    func testDenoiserOptions() {
        let settings = UpscaleSettings()
        
        #expect(settings.denoisers.contains("bm3d"))
        #expect(settings.denoisers.contains("nlmeans"))
        #expect(settings.denoisers.contains("hqdn3d"))
        #expect(settings.denoisers.contains("atadenoise"))
    }
    
    @Test("Settings should have valid hardware acceleration options")
    func testHwAccelOptions() {
        let settings = UpscaleSettings()
        
        #expect(settings.hwAccels.contains("none"))
        #expect(settings.hwAccels.contains("videotoolbox"))
        
        // Note: CUDA is not available on macOS usually, and logic in file depends on arch.
        // We verify the common ones.
    }
    
    @Test("Snapshot carries metal pipeline configuration")
    func testSnapshotMetalFieldsPersisted() {
        let settings = UpscaleSettings()
        settings.enableColorLinearize = false
        settings.useTemporalSmoothing = true
        settings.tileFeatherMargin = "8"
        settings.moireStrength = "0.4"
        
        let snapshot = UpscaleSettingsSnapshot(settings: settings)
        #expect(snapshot.enableColorLinearize == false)
        #expect(snapshot.useTemporalSmoothing == true)
        #expect(snapshot.tileFeatherMargin == "8")
        #expect(snapshot.moireStrength == "0.4")
    }
}

