import Foundation
@testable import myUpscaler

class MockAssetLoader: AssetLoaderProtocol {
    
    var durationToReturn: Double = 60.0
    var errorToThrow: Error?
    
    func loadDuration(from path: String) async throws -> Double {
        if let error = errorToThrow {
            throw error
        }
        return durationToReturn
    }
}

