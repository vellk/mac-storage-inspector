import Foundation

/// Applies known filesystem mutations to a completed scan without traversing the disk again.
public enum FileTreeUpdater {
    public static func removing(_ urls: [URL], from root: FileNode) -> FileNode? {
        let removedPaths = Set(urls.map { $0.standardizedFileURL.path })
        guard !removedPaths.isEmpty else { return root }

        func isRemoved(_ node: FileNode) -> Bool {
            let path = node.url.standardizedFileURL.path
            return removedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        let nodes = root.flattened()
        let remainingNodes = nodes.filter { !isRemoved($0) }
        var removedContributions: [FileIdentity: (logical: Int64, allocated: Int64)] = [:]
        for node in nodes where isRemoved(node) && node.kind == .file && !node.isDuplicateHardLink {
            if let identity = node.identity {
                removedContributions[identity] = (node.logicalBytes, node.allocatedBytes)
            }
        }

        // If another hard link remains, promote it to carry the identity's contribution.
        var promotions: [String: (logical: Int64, allocated: Int64)] = [:]
        for (identity, sizes) in removedContributions {
            if let replacement = remainingNodes.first(where: { $0.kind == .file && $0.identity == identity }) {
                promotions[replacement.id] = sizes
            }
        }

        func rebuild(_ node: FileNode) -> FileNode? {
            guard !isRemoved(node) else { return nil }
            if node.isDirectory {
                let children = node.children.compactMap(rebuild).sorted { $0.allocatedBytes > $1.allocatedBytes }
                return FileNode(url: node.url, kind: node.kind, identity: node.identity,
                    logicalBytes: children.reduce(0) { $0 + $1.logicalBytes },
                    allocatedBytes: children.reduce(0) { $0 + $1.allocatedBytes },
                    fileCount: children.reduce(0) { $0 + $1.fileCount }, modified: node.modified,
                    isWritable: node.isWritable, warning: node.warning, children: children)
            }
            if let sizes = promotions[node.id] {
                return FileNode(url: node.url, kind: node.kind, identity: node.identity,
                    logicalBytes: sizes.logical, allocatedBytes: sizes.allocated, fileCount: 1,
                    modified: node.modified, isWritable: node.isWritable, isDuplicateHardLink: false,
                    warning: node.warning, children: node.children)
            }
            return node
        }
        return rebuild(root)
    }
}
