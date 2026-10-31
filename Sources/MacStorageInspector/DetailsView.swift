import SwiftUI
import StorageCore

struct DetailsView: View {
    @EnvironmentObject private var model: ScanCoordinator
    let node: FileNode?
    var body: some View {
        if let node {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill").font(.largeTitle).foregroundStyle(Color.accentColor); Text(node.name).font(.title2.bold()).textSelection(.enabled) }
                    GroupBox("Location") { Text(node.url.path).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
                    GroupBox("Size") {
                        DetailLine(label: "Allocated", value: StorageFormatting.byteCount(node.allocatedBytes))
                        DetailLine(label: "Logical", value: StorageFormatting.byteCount(node.logicalBytes))
                        DetailLine(label: "Files", value: node.fileCount.formatted())
                        if let modified = node.modified { DetailLine(label: "Modified", value: modified.formatted(date: .abbreviated, time: .shortened)) }
                    }
                    GroupBox("Caution") {
                        VStack(alignment: .leading, spacing: 5) { Label(node.warning.rawValue, systemImage: warningIcon).font(.headline); Text(node.warning.explanation).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                    }
                    GroupBox("Access") { DetailLine(label: "Writable", value: node.isWritable ? "Yes" : "No"); DetailLine(label: "Type", value: node.kind.rawValue.capitalized) }
                    VStack(spacing: 8) {
                        Button("Reveal in Finder", systemImage: "finder") { model.reveal(node) }.frame(maxWidth: .infinity)
                        Button("Copy Path", systemImage: "doc.on.doc") { model.copyPath(node) }.frame(maxWidth: .infinity)
                        Button("Rescan This Item", systemImage: "arrow.clockwise") { model.rescanFocused() }.frame(maxWidth: .infinity)
                        Button(model.selectedIDs.contains(node.id) ? "Remove from Trash Selection" : "Select for Trash", systemImage: "trash") { model.toggleSelection(node) }
                            .buttonStyle(.borderedProminent).tint(.orange).frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }.padding()
            }.navigationTitle("Details")
        } else { ContentUnavailableView("Select an Item", systemImage: "sidebar.right", description: Text("Choose a file or folder to inspect its exact path, size, and caution category.")) }
    }
    private var warningIcon: String { node?.warning == .systemProtected ? "lock.fill" : "exclamationmark.triangle.fill" }
}

struct DetailLine: View {
    let label: String; let value: String
    var body: some View { HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit().textSelection(.enabled) }.padding(.vertical, 2) }
}

struct SelectionBar: View {
    @EnvironmentObject private var model: ScanCoordinator
    var body: some View {
        HStack { Label("\(model.selectedNodes.count) selected", systemImage: "checkmark.square"); Text("Estimated allocated: \(StorageFormatting.byteCount(model.selectedBytes))").foregroundStyle(.secondary); Spacer(); Button("Clear") { model.selectedIDs.removeAll() }; Button("Review Selection") { model.showsTrashReview = true }.buttonStyle(.borderedProminent).tint(.orange) }
            .padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial).overlay(alignment: .top) { Divider() }
    }
}
