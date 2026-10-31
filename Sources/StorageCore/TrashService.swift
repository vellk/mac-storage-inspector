import Foundation

public struct TrashResult: Identifiable, Sendable {
    public let id = UUID()
    public let originalURL: URL
    public let trashedURL: URL?
    public let errorDescription: String?
    public var succeeded: Bool { errorDescription == nil }
    public init(originalURL: URL, trashedURL: URL?, errorDescription: String?) {
        self.originalURL = originalURL; self.trashedURL = trashedURL; self.errorDescription = errorDescription
    }
}

public protocol TrashServicing: Sendable {
    func moveToTrash(_ nodes: [FileNode], scope: URL) async -> [TrashResult]
}

public struct TrashService: TrashServicing {
    public init() {}
    public func moveToTrash(_ nodes: [FileNode], scope: URL) async -> [TrashResult] {
        let approved = DeletionPolicy.normalizeSelection(nodes)
        var results: [TrashResult] = []
        for node in approved {
            if Task.isCancelled { break }
            let validation = DeletionPolicy.validate(node.url, within: scope, expectedIdentity: node.identity)
            guard validation.allowed else {
                results.append(.init(originalURL: node.url, trashedURL: nil, errorDescription: validation.reason)); continue
            }
            do {
                var destination: NSURL?
                try FileManager.default.trashItem(at: node.url, resultingItemURL: &destination)
                results.append(.init(originalURL: node.url, trashedURL: destination as URL?, errorDescription: nil))
            } catch {
                results.append(.init(originalURL: node.url, trashedURL: nil, errorDescription: error.localizedDescription))
            }
        }
        return results
    }
}
