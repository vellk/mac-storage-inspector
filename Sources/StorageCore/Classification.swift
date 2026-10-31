import Foundation

public enum PathClassifier {
    public static func warning(for url: URL, kind: NodeKind, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> WarningCategory {
        if DeletionPolicy.isProtected(url, home: home) { return .systemProtected }
        if kind == .package { return .package }
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if path.hasPrefix(homePath + "/Library/Containers/") ||
            path.hasPrefix(homePath + "/Library/Group Containers/") ||
            path.hasPrefix(homePath + "/Library/Application Support/") { return .applicationData }
        if path.contains("/.git/") || path.hasSuffix("/.git") ||
            path.hasPrefix(homePath + "/.docker/") || path.hasPrefix(homePath + "/.orbstack/") ||
            path.hasPrefix(homePath + "/Library/Developer/") { return .developerData }
        if path.hasPrefix(homePath + "/Library/Caches/") { return .likelyRegenerable }
        if path.hasPrefix(homePath + "/Documents/") || path.hasPrefix(homePath + "/Pictures/") ||
            path.hasPrefix(homePath + "/Desktop/") { return .potentiallyValuable }
        return .unknown
    }
}
