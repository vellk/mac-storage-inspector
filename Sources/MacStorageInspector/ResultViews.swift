import SwiftUI
import StorageCore

struct TreeBrowserView: View {
    let root: FileNode?
    var body: some View {
        VStack(spacing: 0) {
            TableHeader()
            Divider()
            if let root {
                ScrollView { LazyVStack(spacing: 0) { NodeBranch(node: root, depth: 0, initiallyExpanded: true) } }
            } else { ContentUnavailableView("No Results", systemImage: "folder") }
        }
    }
}

struct TableHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Allocated").frame(width: 90, alignment: .trailing)
            Text("Logical").frame(width: 90, alignment: .trailing)
            Text("Share").frame(width: 76, alignment: .trailing)
            Text("Items").frame(width: 62, alignment: .trailing)
        }.font(.caption.bold()).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 8)
    }
}

struct NodeBranch: View {
    @EnvironmentObject private var model: ScanCoordinator
    let node: FileNode
    let depth: Int
    @State var expanded: Bool

    init(node: FileNode, depth: Int, initiallyExpanded: Bool = false) {
        self.node = node; self.depth = depth; _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        NodeRow(node: node, depth: depth, expanded: $expanded)
        if expanded {
            ForEach(node.children) { child in NodeBranch(node: child, depth: depth + 1) }
        }
    }
}

struct NodeRow: View {
    @EnvironmentObject private var model: ScanCoordinator
    let node: FileNode
    let depth: Int
    @Binding var expanded: Bool
    private var rootBytes: Int64 { model.snapshot?.rootNode?.allocatedBytes ?? 0 }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Color.clear.frame(width: CGFloat(depth * 14))
                if node.isDirectory {
                    Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 12) }
                        .buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse" : "Expand")
                } else { Color.clear.frame(width: 12) }
                Button { model.toggleSelection(node) } label: {
                    Image(systemName: model.selectedIDs.contains(node.id) ? "checkmark.square.fill" : "square")
                        .foregroundStyle(model.selectedIDs.contains(node.id) ? Color.accentColor : .secondary)
                }.buttonStyle(.plain).accessibilityLabel("Select \(node.name) for Trash")
                Image(systemName: icon).foregroundStyle(iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name).lineLimit(1)
                    if node.isDuplicateHardLink { Text("Hard link already counted").font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(StorageFormatting.byteCount(node.allocatedBytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
            Text(StorageFormatting.byteCount(node.logicalBytes)).monospacedDigit().frame(width: 90, alignment: .trailing)
            ShareBar(value: node.share(of: rootBytes)).frame(width: 76)
            Text(node.fileCount.formatted()).monospacedDigit().frame(width: 62, alignment: .trailing)
        }
        .font(.callout).padding(.horizontal, 12).padding(.vertical, 6)
        .background(model.focusedNode?.id == node.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle()).onTapGesture { model.focusedNode = node }
        .contextMenu {
            Button("Reveal in Finder") { model.reveal(node) }
            Button("Copy Path") { model.copyPath(node) }
            Divider()
            Button(model.selectedIDs.contains(node.id) ? "Remove from Selection" : "Select for Trash") { model.toggleSelection(node) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name), allocated \(StorageFormatting.byteCount(node.allocatedBytes)), \(node.fileCount) items")
    }
    private var icon: String {
        switch node.kind { case .directory: "folder.fill"; case .package: "shippingbox.fill"; case .symbolicLink: "link"; case .file: "doc.fill"; case .other: "questionmark.square" }
    }
    private var iconColor: Color { node.kind == .directory ? .accentColor : (node.kind == .package ? .purple : .secondary) }
}

struct ShareBar: View {
    let value: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            GeometryReader { proxy in Capsule().fill(Color.accentColor.opacity(0.7)).frame(width: proxy.size.width * min(max(value, 0), 1)) }
        }.frame(height: 6).overlay(alignment: .trailing) { Text(value, format: .percent.precision(.fractionLength(0))).font(.caption2).offset(y: -11) }
    }
}

struct RankedList: View {
    @EnvironmentObject private var model: ScanCoordinator
    let nodes: [FileNode]
    let title: String
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(title).font(.title2.bold()); Spacer(); Text("Top \(nodes.count)").foregroundStyle(.secondary) }.padding()
            List(nodes) { node in
                HStack {
                    Button { model.toggleSelection(node) } label: { Image(systemName: model.selectedIDs.contains(node.id) ? "checkmark.square.fill" : "square") }.buttonStyle(.plain)
                    Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill").foregroundStyle(node.isDirectory ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading) { Text(node.name); Text(node.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                    Spacer(); Text(StorageFormatting.byteCount(node.allocatedBytes)).monospacedDigit()
                }.contentShape(Rectangle()).onTapGesture { model.focusedNode = node }
            }
        }
    }
}

struct IssuesView: View {
    let issues: [ScanIssue]
    var body: some View {
        if issues.isEmpty { ContentUnavailableView("No Scan Issues", systemImage: "checkmark.circle", description: Text("All visited paths were readable and stayed within the selected filesystem.")) }
        else {
            List(issues) { issue in
                VStack(alignment: .leading, spacing: 4) { Text(issue.path).font(.callout.monospaced()).textSelection(.enabled); Text(issue.message).foregroundStyle(.secondary) }
                    .padding(.vertical, 3)
            }.navigationTitle("Scan Issues")
        }
    }
}
