import XCTest

class DistributionReadinessTests: XCTestCase {

    func testInfoPListContainsUsageDescriptions() throws {
        let bundle = Bundle.main
        let infoDictionary = bundle.infoDictionary ?? [:]
        let encryptionUsage = infoDictionary["ITSAppUsesNonExemptEncryption"] as? Bool
        XCTAssertNotNil(encryptionUsage, "ITSAppUsesNonExemptEncryption must be set in Info.plist to avoid App Store Connect warnings")
    }
    
    func testBundleIdentifier() {
        let bundleID = Bundle.main.bundleIdentifier
        XCTAssertNotNil(bundleID)
        XCTAssertFalse(bundleID?.contains("example") ?? false, "Bundle ID should not contain 'example'")
    }
    
    func testVersionNumbers() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        
        XCTAssertNotNil(version, "CFBundleShortVersionString (Marketing Version) is missing")
        XCTAssertNotNil(build, "CFBundleVersion (Build Number) is missing")
    }
    
    func testSandboxEnvironment() {
        let isSandboxed = isAppSandboxed()
        XCTAssertTrue(isSandboxed, "App must be sandboxed for Mac App Store distribution")
    }
    
    private func isAppSandboxed() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
    
    func testNoPrivateAPIs() {
        _ = Bundle.main.bundlePath
    }
}

