import SwiftUI
import UniformTypeIdentifiers
import StorageCore

struct ContentView: View {
    @EnvironmentObject private var model: ScanCoordinator
    @State private var choosingFolder = false
    @State private var showsDataWarning = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            VStack(spacing: 0) {
                CapacitySummary(snapshot: model.snapshot)
                Divider()
                MainResultsView()
            }
            .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        } detail: {
            DetailsView(node: model.focusedNode)
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        }
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { if !model.selectedIDs.isEmpty { SelectionBar() } }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.startScan(url, securityScoped: true) }
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
        .confirmationDialog("Scan Data Volume?", isPresented: $showsDataWarning, titleVisibility: .visible) {
            Button("Scan /System/Volumes/Data") { model.scanDataVolume() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("macOS privacy controls may make parts of the volume unreadable. The app will report those paths and will never request elevated privileges.") }
        .sheet(isPresented: $model.showsTrashReview) { TrashReviewView() }
        .sheet(isPresented: $model.showsTrashResults) { TrashResultsView() }
        .alert("Mac Storage Inspector", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Scan Home", systemImage: "house") { model.scanHome() }
                Button("Choose Folder…", systemImage: "folder.badge.plus") { choosingFolder = true }
                Divider()
                Button("Scan Data Volume…", systemImage: "externaldrive") { showsDataWarning = true }
            } label: { Label(model.snapshot == nil ? "Scan" : "New Scan", systemImage: "magnifyingglass") }
            if model.isScanning { Button("Cancel", systemImage: "xmark.circle") { model.cancel() } }
            else if model.snapshot != nil { Button("Rescan", systemImage: "arrow.clockwise") { model.rescan() } }
        }
        ToolbarItem(placement: .status) { ScanStatusView() }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        List(NavigationSection.allCases, selection: $model.selectedSection) { section in
            Label(section.rawValue, systemImage: section.icon).tag(section)
        }
        .navigationTitle("Storage")
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let root = model.snapshot?.root { Text(root.path).lineLimit(2).font(.caption).foregroundStyle(.secondary) }
                if let snapshot = model.snapshot { Text(snapshot.completeness.rawValue.capitalized).font(.caption.bold()).foregroundStyle(snapshot.completeness == .complete ? .green : .orange) }
            }.padding()
        }
    }
}

struct ScanStatusView: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        HStack(spacing: 8) {
            if model.isScanning { ProgressView().controlSize(.small) }
            Text(model.isScanning ? "\(model.progress.filesScanned.formatted()) files • \(StorageFormatting.byteCount(model.progress.bytesAggregated))" : "Ready")
                .font(.caption).foregroundStyle(.secondary)
        }.accessibilityLabel(model.isScanning ? "Scanning, \(model.progress.filesScanned) files" : "Ready")
    }
}

struct CapacitySummary: View {
    let snapshot: DiskUsageSnapshot?
    var body: some View {
        HStack(spacing: 24) {
            Metric(title: "Volume Used", value: StorageFormatting.byteCount(snapshot?.capacity.used))
            Metric(title: "Available", value: StorageFormatting.byteCount(snapshot?.capacity.available))
            Metric(title: "Volume Total", value: StorageFormatting.byteCount(snapshot?.capacity.total))
            Metric(title: "Scanned Accessible", value: StorageFormatting.byteCount(snapshot?.rootNode?.allocatedBytes), tint: .accentColor)
            Spacer()
        }.padding(14).background(.bar)
    }
    struct Metric: View {
        let title: String; let value: String; var tint: Color = .primary
        var body: some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint) } }
    }
}

struct MainResultsView: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        Group {
            if model.snapshot == nil && !model.isScanning { WelcomeView() }
            else if model.isScanning && model.snapshot == nil { ScanningView() }
            else {
                switch model.selectedSection ?? .browser {
                case .browser: TreeBrowserView(root: model.snapshot?.rootNode)
                case .directories: RankedList(nodes: model.snapshot?.rootNode?.topDirectories() ?? [], title: "Largest Directories")
                case .files: RankedList(nodes: model.snapshot?.rootNode?.topFiles() ?? [], title: "Largest Files")
                case .issues: IssuesView(issues: model.snapshot?.issues ?? [])
                }
            }
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        ContentUnavailableView {
            Label("Understand Your Mac Storage", systemImage: "internaldrive")
        } description: {
            Text("Scan metadata locally. Nothing is uploaded, automatically cleaned, or permanently deleted.")
        } actions: { Button("Scan Home") { model.scanHome() }.buttonStyle(.borderedProminent) }
    }
}

struct ScanningView: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Scanning…").font(.title2.bold())
            Text("\(model.progress.filesScanned.formatted()) files • \(StorageFormatting.byteCount(model.progress.bytesAggregated)) accessible allocated bytes")
            Text(model.progress.currentPath).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).padding(.horizontal, 40)
            Button("Cancel") { model.cancel() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
