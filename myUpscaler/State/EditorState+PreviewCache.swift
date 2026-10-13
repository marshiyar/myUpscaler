import Foundation

nonisolated struct PreviewRequestKey: Hashable, Sendable {
    let frameGeneration: UUID
    let parameters: PreviewFilterParameters
}

/// NSCache requires reference keys, but equality is defined by the typed request.
nonisolated final class PreviewCacheKey: NSObject {
    let request: PreviewRequestKey
    init(_ request: PreviewRequestKey) { self.request = request }
    override var hash: Int { request.hashValue }
    override func isEqual(_ object: Any?) -> Bool {
        (object as? PreviewCacheKey)?.request == request
    }
}
