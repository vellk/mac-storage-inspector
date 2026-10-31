import Foundation
import Darwin

public struct ScanOptions: Sendable {
    public var excludedPaths: Set<String>
    public var stayOnVolume: Bool
    public var updateEvery: Int
    public init(excludedPaths: Set<String> = [], stayOnVolume: Bool = true, updateEvery: Int = 200) {
        self.excludedPaths = Set(excludedPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        self.stayOnVolume = stayOnVolume; self.updateEvery = max(1, updateEvery)
    }
}

public protocol FileSystemScanning: Sendable {
    func scan(root: URL, options: ScanOptions,
              onProgress: @escaping @Sendable (ScanProgress) async -> Void,
              onPartialRoot: @escaping @Sendable (FileNode) async -> Void) async -> DiskUsageSnapshot
}

public struct FileSystemScanner: FileSystemScanning {
    private let capacityProvider: any VolumeInfoProviding
    public init(capacityProvider: any VolumeInfoProviding = VolumeInfoProvider()) { self.capacityProvider = capacityProvider }

    public func scan(root: URL, options: ScanOptions = ScanOptions(),
                     onProgress: @escaping @Sendable (ScanProgress) async -> Void = { _ in },
                     onPartialRoot: @escaping @Sendable (FileNode) async -> Void = { _ in }) async -> DiskUsageSnapshot {
        let root = root.standardizedFileURL
        let started = Date()
        let capacity = (try? capacityProvider.capacity(for: root)) ?? VolumeCapacity(total: nil, available: nil)
        var state = State(options: options, rootDevice: metadata(root)?.identity.volume)
        let node = await visit(root, depth: 0, state: &state, onProgress: onProgress, onPartialRoot: onPartialRoot)
        let cancelled = Task.isCancelled
        let completeness: ScanCompleteness = cancelled ? .cancelled : (state.issues.isEmpty ? .complete : .incomplete)
        let progress = state.progress(current: root.path)
        await onProgress(progress)
        return DiskUsageSnapshot(root: root, startedAt: started, finishedAt: Date(), completeness: completeness,
            capacity: capacity, rootNode: node, issues: state.issues, progress: progress)
    }

    private struct Metadata {
        let identity: FileIdentity
        let kind: NodeKind
        let logical: Int64
        let allocated: Int64
        let modified: Date?
        let writable: Bool
    }

    private struct State {
        var options: ScanOptions
        var rootDevice: UInt64?
        var seenFiles = Set<FileIdentity>()
        var files = 0
        var bytes: Int64 = 0
        var issues: [ScanIssue] = []
        func progress(current: String) -> ScanProgress { .init(filesScanned: files, bytesAggregated: bytes, currentPath: current, issues: issues.count) }
    }

    private func visit(_ url: URL, depth: Int, state: inout State,
                       onProgress: @escaping @Sendable (ScanProgress) async -> Void,
                       onPartialRoot: @escaping @Sendable (FileNode) async -> Void) async -> FileNode? {
        guard !Task.isCancelled else { return nil }
        let path = url.standardizedFileURL.path
        if state.options.excludedPaths.contains(path) {
            state.issues.append(.init(path: path, message: "Excluded by user settings")); return nil
        }
        guard let meta = metadata(url) else {
            state.issues.append(.init(path: path, message: String(cString: strerror(errno)))); return nil
        }
        if state.options.stayOnVolume, let rootDevice = state.rootDevice, meta.identity.volume != rootDevice {
            state.issues.append(.init(path: path, message: "Skipped: different filesystem")); return nil
        }

        if meta.kind == .symbolicLink || meta.kind == .file || meta.kind == .other {
            let duplicate = meta.kind == .file && !state.seenFiles.insert(meta.identity).inserted
            state.files += duplicate ? 0 : 1
            state.bytes += duplicate ? 0 : meta.allocated
            if state.files % state.options.updateEvery == 0 { await onProgress(state.progress(current: path)) }
            return FileNode(url: url, kind: meta.kind, identity: meta.identity,
                logicalBytes: duplicate ? 0 : meta.logical, allocatedBytes: duplicate ? 0 : meta.allocated,
                fileCount: duplicate ? 0 : 1, modified: meta.modified, isWritable: meta.writable,
                isDuplicateHardLink: duplicate, warning: PathClassifier.warning(for: url, kind: meta.kind))
        }

        var children: [FileNode] = []
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [], options: [])
            for child in urls {
                if let node = await visit(child, depth: depth + 1, state: &state, onProgress: onProgress, onPartialRoot: onPartialRoot) {
                    children.append(node)
                    if depth == 0 {
                        children.sort { $0.allocatedBytes > $1.allocatedBytes }
                        let partial = FileNode(url: url, kind: meta.kind, identity: meta.identity,
                            logicalBytes: children.reduce(0) { $0 + $1.logicalBytes },
                            allocatedBytes: children.reduce(0) { $0 + $1.allocatedBytes },
                            fileCount: children.reduce(0) { $0 + $1.fileCount }, modified: meta.modified,
                            isWritable: meta.writable, warning: PathClassifier.warning(for: url, kind: meta.kind), children: children)
                        await onPartialRoot(partial)
                    }
                }
                if Task.isCancelled { break }
            }
        } catch {
            state.issues.append(.init(path: path, message: error.localizedDescription))
        }
        children.sort { $0.allocatedBytes > $1.allocatedBytes }
        let logical = children.reduce(0) { $0 + $1.logicalBytes }
        let allocated = children.reduce(0) { $0 + $1.allocatedBytes }
        let count = children.reduce(0) { $0 + $1.fileCount }
        return FileNode(url: url, kind: meta.kind, identity: meta.identity, logicalBytes: logical,
            allocatedBytes: allocated, fileCount: count, modified: meta.modified, isWritable: meta.writable,
            warning: PathClassifier.warning(for: url, kind: meta.kind), children: children)
    }

    private func metadata(_ url: URL) -> Metadata? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let mode = info.st_mode & S_IFMT
        let kind: NodeKind
        if mode == S_IFLNK { kind = .symbolicLink }
        else if mode == S_IFDIR {
            let values = try? url.resourceValues(forKeys: [.isPackageKey])
            kind = values?.isPackage == true ? .package : .directory
        } else if mode == S_IFREG { kind = .file } else { kind = .other }
        return Metadata(identity: .init(volume: UInt64(info.st_dev), inode: UInt64(info.st_ino)), kind: kind,
            logical: Int64(info.st_size), allocated: Int64(info.st_blocks) * 512,
            modified: Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)),
            writable: FileManager.default.isWritableFile(atPath: url.path))
    }
}
