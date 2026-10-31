import Foundation
import Darwin

public struct DeletionValidation: Sendable, Equatable {
    public let allowed: Bool
    public let reason: String?
    public let requiresExtraConfirmation: Bool
    public init(allowed: Bool, reason: String? = nil, requiresExtraConfirmation: Bool = false) {
        self.allowed = allowed; self.reason = reason; self.requiresExtraConfirmation = requiresExtraConfirmation
    }
}

public enum DeletionPolicy {
    private static let protectedPaths = [
        "/", "/System", "/System/Volumes", "/System/Volumes/Data", "/Applications", "/Library",
        "/private", "/usr", "/bin", "/sbin", "/dev", "/Volumes"
    ]

    public static func isProtected(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                   bundleURL: URL? = Bundle.main.bundleURL) -> Bool {
        let path = normalized(url)
        let homePath = normalized(home)
        if path == homePath { return true }
        let protectedHomeCategories = [
            homePath + "/Library", homePath + "/Library/Containers",
            homePath + "/Library/Group Containers", homePath + "/Library/Application Support",
            homePath + "/.docker", homePath + "/.orbstack"
        ]
        if protectedHomeCategories.contains(path) { return true }
        var protected = protectedPaths
        if let bundleURL {
            let bundlePath = normalized(bundleURL)
            if path == bundlePath || path.hasPrefix(bundlePath + "/") { return true }
            protected.append(bundlePath)
        }
        if let executableURL = Bundle.main.executableURL { protected.append(normalized(executableURL)) }
        for item in protected {
            if path == item || item.hasPrefix(path == "/" ? path : path + "/") { return true }
        }
        if isVolumeRoot(url) { return true }
        return false
    }

    public static func validate(_ url: URL, within scope: URL,
                                expectedIdentity: FileIdentity? = nil,
                                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                bundleURL: URL? = Bundle.main.bundleURL) -> DeletionValidation {
        let path = normalized(url)
        let scopePath = normalized(scope)
        guard path != scopePath, path.hasPrefix(scopePath == "/" ? "/" : scopePath + "/") else {
            return .init(allowed: false, reason: "The item is outside the selected scope, or is the scope root itself.")
        }
        guard !isProtected(url, home: home, bundleURL: bundleURL) else {
            return .init(allowed: false, reason: "This item is a protected location or an ancestor of one.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            return .init(allowed: false, reason: "The item no longer exists.")
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return .init(allowed: false, reason: "The item is not writable with current permissions.")
        }
        if let expectedIdentity {
            guard identity(at: url) == expectedIdentity else {
                return .init(allowed: false, reason: "The item changed since it was scanned.")
            }
        }
        let warning = PathClassifier.warning(for: url, kind: .other, home: home)
        let package = (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true
        let extra = warning == .applicationData || warning == .developerData || package || normalized(url).hasPrefix(normalized(home) + "/Library/")
        return .init(allowed: true, requiresExtraConfirmation: extra)
    }

    public static func normalizeSelection(_ nodes: [FileNode]) -> [FileNode] {
        let sorted = nodes.sorted { normalized($0.url).count < normalized($1.url).count }
        var result: [FileNode] = []
        for node in sorted {
            let path = normalized(node.url)
            if !result.contains(where: { path.hasPrefix(normalized($0.url) + "/") }) { result.append(node) }
        }
        return result.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    public static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "" ? "/" : url.standardizedFileURL.path
    }

    private static func identity(at url: URL) -> FileIdentity? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return .init(volume: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func isVolumeRoot(_ url: URL) -> Bool {
        let path = normalized(url)
        guard let values = try? url.resourceValues(forKeys: [.volumeURLKey]), let volume = values.volume else { return path == "/" }
        return normalized(volume) == path
    }
}
