import Foundation

public enum NodeKind: String, Codable, Sendable {
    case file, directory, symbolicLink, package, other
}

public enum WarningCategory: String, Codable, CaseIterable, Sendable {
    case unknown = "Unknown"
    case likelyRegenerable = "Likely regenerable"
    case potentiallyValuable = "Potentially valuable data"
    case applicationData = "Application data"
    case developerData = "Developer data"
    case package = "Package or application"
    case systemProtected = "System-protected"

    public var explanation: String {
        switch self {
        case .unknown: "Ownership and recoverability are unknown. Review before moving to Trash."
        case .likelyRegenerable: "The path looks cache-like, but this classification is advisory."
        case .potentiallyValuable: "This location commonly contains user-created or important data."
        case .applicationData: "Applications may rely on this data for settings, accounts, or documents."
        case .developerData: "This may contain source history, build products, simulators, or tool data."
        case .package: "This is a bundle. Treat it as one advanced item and verify its purpose."
        case .systemProtected: "This location is protected and cannot be selected for Trash."
        }
    }
}

public struct FileIdentity: Hashable, Codable, Sendable {
    public let volume: UInt64
    public let inode: UInt64
    public init(volume: UInt64, inode: UInt64) { self.volume = volume; self.inode = inode }
}

public struct FileNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let name: String
    public let kind: NodeKind
    public let identity: FileIdentity?
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let fileCount: Int
    public let modified: Date?
    public let isWritable: Bool
    public let isDuplicateHardLink: Bool
    public let warning: WarningCategory
    public let children: [FileNode]

    public init(
        url: URL, kind: NodeKind, identity: FileIdentity? = nil,
        logicalBytes: Int64 = 0, allocatedBytes: Int64 = 0, fileCount: Int = 0,
        modified: Date? = nil, isWritable: Bool = false, isDuplicateHardLink: Bool = false,
        warning: WarningCategory = .unknown, children: [FileNode] = []
    ) {
        self.url = url.standardizedFileURL
        self.id = identity.map { "\($0.volume):\($0.inode):\(url.path)" } ?? url.standardizedFileURL.path
        self.name = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        self.kind = kind
        self.identity = identity
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.fileCount = fileCount
        self.modified = modified
        self.isWritable = isWritable
        self.isDuplicateHardLink = isDuplicateHardLink
        self.warning = warning
        self.children = children
    }

    public var isDirectory: Bool { kind == .directory || kind == .package }
    public func share(of root: Int64) -> Double { root > 0 ? Double(allocatedBytes) / Double(root) : 0 }
}

public struct ScanIssue: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let path: String
    public let message: String
    public init(path: String, message: String) { self.path = path; self.message = message }
}

public struct VolumeCapacity: Hashable, Sendable {
    public let total: Int64?
    public let available: Int64?
    public var used: Int64? {
        guard let total, let available else { return nil }
        return max(0, total - available)
    }
    public init(total: Int64?, available: Int64?) { self.total = total; self.available = available }
}

public enum ScanCompleteness: String, Sendable { case scanning, complete, cancelled, incomplete }

public struct ScanProgress: Sendable {
    public let filesScanned: Int
    public let bytesAggregated: Int64
    public let currentPath: String
    public let issues: Int
    public init(filesScanned: Int, bytesAggregated: Int64, currentPath: String, issues: Int) {
        self.filesScanned = filesScanned; self.bytesAggregated = bytesAggregated
        self.currentPath = currentPath; self.issues = issues
    }
}

public struct DiskUsageSnapshot: Sendable {
    public let root: URL
    public let startedAt: Date
    public let finishedAt: Date?
    public let completeness: ScanCompleteness
    public let capacity: VolumeCapacity
    public let rootNode: FileNode?
    public let issues: [ScanIssue]
    public let progress: ScanProgress
    public init(root: URL, startedAt: Date, finishedAt: Date?, completeness: ScanCompleteness,
                capacity: VolumeCapacity, rootNode: FileNode?, issues: [ScanIssue], progress: ScanProgress) {
        self.root = root; self.startedAt = startedAt; self.finishedAt = finishedAt
        self.completeness = completeness; self.capacity = capacity; self.rootNode = rootNode
        self.issues = issues; self.progress = progress
    }
}

public extension FileNode {
    func flattened() -> [FileNode] { [self] + children.flatMap { $0.flattened() } }
    func topFiles(limit: Int = 100) -> [FileNode] {
        Array(flattened().filter { $0.kind == .file || $0.kind == .symbolicLink }
            .sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(limit))
    }
    func topDirectories(limit: Int = 100) -> [FileNode] {
        Array(flattened().filter(\.isDirectory)
            .sorted { $0.allocatedBytes > $1.allocatedBytes }.prefix(limit))
    }
}
