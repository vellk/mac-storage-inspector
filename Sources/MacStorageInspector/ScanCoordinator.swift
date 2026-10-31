import AppKit
import Foundation
import StorageCore

enum NavigationSection: String, CaseIterable, Identifiable {
    case browser = "Browse"
    case directories = "Largest Directories"
    case files = "Largest Files"
    case issues = "Scan Issues"
    var id: String { rawValue }
    var icon: String {
        switch self { case .browser: "folder"; case .directories: "list.bullet.indent"; case .files: "doc"; case .issues: "exclamationmark.triangle" }
    }
}

@MainActor
final class ScanCoordinator: ObservableObject {
    @Published var snapshot: DiskUsageSnapshot?
    @Published var progress = ScanProgress(filesScanned: 0, bytesAggregated: 0, currentPath: "", issues: 0)
    @Published var isScanning = false
    @Published var selectedSection: NavigationSection? = .browser
    @Published var focusedNode: FileNode?
    @Published var selectedIDs = Set<String>()
    @Published var excludedPaths: [String] = UserDefaults.standard.stringArray(forKey: "excludedPaths") ?? []
    @Published var trashResults: [TrashResult] = []
    @Published var showsTrashReview = false
    @Published var showsTrashResults = false
    @Published var errorMessage: String?

    private var scanTask: Task<Void, Never>?
    private var scanID = UUID()
    let scanner = FileSystemScanner()
    let trashService = TrashService()

    var root: URL? { snapshot?.root }
    var allNodes: [FileNode] { snapshot?.rootNode?.flattened() ?? [] }
    var selectedNodes: [FileNode] { DeletionPolicy.normalizeSelection(allNodes.filter { selectedIDs.contains($0.id) }) }
    var selectedBytes: Int64 { selectedNodes.reduce(0) { $0 + $1.allocatedBytes } }

    func scanHome() { startScan(FileManager.default.homeDirectoryForCurrentUser) }
    func scanDataVolume() { startScan(URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)) }

    func startScan(_ url: URL, securityScoped: Bool = false) {
        cancel()
        let scopedAccessStarted = securityScoped && url.startAccessingSecurityScopedResource()
        snapshot = nil; selectedIDs.removeAll(); focusedNode = nil
        scanID = UUID()
        let thisScanID = scanID
        isScanning = true
        progress = .init(filesScanned: 0, bytesAggregated: 0, currentPath: url.path, issues: 0)
        let options = ScanOptions(excludedPaths: Set(excludedPaths))
        let scanner = scanner
        let startedAt = Date()
        scanTask = Task { [weak self] in
            let worker = Task.detached(priority: .userInitiated) {
                await scanner.scan(root: url, options: options) { update in
                    await MainActor.run { if self?.scanID == thisScanID { self?.progress = update } }
                } onPartialRoot: { rootNode in
                    await MainActor.run {
                        guard let self, self.scanID == thisScanID else { return }
                        self.snapshot = DiskUsageSnapshot(root: url, startedAt: startedAt, finishedAt: nil,
                            completeness: .scanning, capacity: VolumeCapacity(total: nil, available: nil),
                            rootNode: rootNode, issues: [], progress: self.progress)
                    }
                }
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            if scopedAccessStarted { url.stopAccessingSecurityScopedResource() }
            guard let self, self.scanID == thisScanID else { return }
            snapshot = result; progress = result.progress; isScanning = false
        }
    }

    func cancel() {
        scanID = UUID()
        scanTask?.cancel(); scanTask = nil
        if isScanning {
            isScanning = false
            if let current = snapshot {
                snapshot = DiskUsageSnapshot(root: current.root, startedAt: current.startedAt, finishedAt: Date(),
                    completeness: .cancelled, capacity: current.capacity, rootNode: current.rootNode,
                    issues: current.issues, progress: progress)
            }
        }
    }

    func rescan() { if let root { startScan(root) } }
    func rescanFocused() { if let focusedNode { startScan(focusedNode.url) } }

    func toggleSelection(_ node: FileNode) {
        if selectedIDs.contains(node.id) { selectedIDs.remove(node.id); return }
        guard let root else { return }
        let validation = DeletionPolicy.validate(node.url, within: root, expectedIdentity: node.identity)
        guard validation.allowed else { errorMessage = validation.reason; return }
        selectedIDs.insert(node.id)
        selectedIDs = Set(DeletionPolicy.normalizeSelection(allNodes.filter { selectedIDs.contains($0.id) }).map(\.id))
    }

    func reveal(_ node: FileNode) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(node.url.path, forType: .string)
    }

    func moveReviewedItemsToTrash() async {
        guard let root else { return }
        let nodes = selectedNodes
        showsTrashReview = false
        let service = trashService
        trashResults = await Task.detached(priority: .userInitiated) {
            await service.moveToTrash(nodes, scope: root)
        }.value
        let removedURLs = trashResults.filter(\.succeeded).map(\.originalURL)
        await applyTrashChanges(removedURLs)
        selectedIDs.removeAll(); showsTrashResults = true
    }

    private func applyTrashChanges(_ removedURLs: [URL]) async {
        guard !removedURLs.isEmpty, let current = snapshot, let currentRoot = current.rootNode else { return }
        let updatedRoot = FileTreeUpdater.removing(removedURLs, from: currentRoot)
        let removedPaths = removedURLs.map { $0.standardizedFileURL.path }
        let updatedIssues = current.issues.filter { issue in
            !removedPaths.contains { issue.path == $0 || issue.path.hasPrefix($0 + "/") }
        }
        let updatedProgress = ScanProgress(filesScanned: updatedRoot?.fileCount ?? 0,
            bytesAggregated: updatedRoot?.allocatedBytes ?? 0, currentPath: current.root.path,
            issues: updatedIssues.count)
        progress = updatedProgress
        if let focusedNode, removedPaths.contains(where: { focusedNode.url.path == $0 || focusedNode.url.path.hasPrefix($0 + "/") }) {
            self.focusedNode = nil
        }

        let thisScanID = scanID
        snapshot = DiskUsageSnapshot(root: current.root, startedAt: current.startedAt, finishedAt: Date(),
            completeness: current.completeness, capacity: current.capacity, rootNode: updatedRoot,
            issues: updatedIssues, progress: updatedProgress)

        let capacityProvider = VolumeInfoProvider()
        let refreshedCapacity = await Task.detached(priority: .utility) {
            (try? capacityProvider.capacity(for: current.root)) ?? current.capacity
        }.value
        guard scanID == thisScanID else { return }
        snapshot = DiskUsageSnapshot(root: current.root, startedAt: current.startedAt, finishedAt: Date(),
            completeness: current.completeness, capacity: refreshedCapacity, rootNode: updatedRoot,
            issues: updatedIssues, progress: updatedProgress)
    }

    func addExclusion(_ path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard !excludedPaths.contains(normalized) else { return }
        excludedPaths.append(normalized); saveSettings()
    }
    func removeExclusions(at offsets: IndexSet) { excludedPaths.remove(atOffsets: offsets); saveSettings() }
    private func saveSettings() { UserDefaults.standard.set(excludedPaths, forKey: "excludedPaths") }
}
