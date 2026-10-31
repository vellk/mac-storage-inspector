import SwiftUI
import StorageCore

struct TrashReviewView: View {
    @EnvironmentObject private var model: ScanCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var understandsRisk = false
    private var risky: Bool {
        model.selectedNodes.contains { node in
            guard let root = model.root else { return true }
            return DeletionPolicy.validate(node.url, within: root, expectedIdentity: node.identity).requiresExtraConfirmation
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Image(systemName: "trash.circle.fill").font(.largeTitle).foregroundStyle(.orange); VStack(alignment: .leading) { Text("Review Move to Trash").font(.title2.bold()); Text("\(model.selectedNodes.count) top-level items • \(StorageFormatting.byteCount(model.selectedBytes)) estimated allocated size").foregroundStyle(.secondary) }; Spacer() }.padding()
            Divider()
            List(model.selectedNodes) { node in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(node.name).font(.headline); Spacer(); Text(StorageFormatting.byteCount(node.allocatedBytes)).monospacedDigit() }
                    Text(node.url.path).font(.caption.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
                    Label(node.warning.rawValue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(node.warning == .unknown ? Color.secondary : Color.orange)
                }.padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Items go to Finder Trash and can be restored. Disk space may not increase until Trash is emptied and APFS snapshots are released.", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                if risky {
                    Label("This selection contains application, developer, or Library data. Apps or tools may stop working or lose data.", systemImage: "exclamationmark.octagon.fill").foregroundStyle(.orange)
                    Toggle("I reviewed the full paths and understand the additional risk", isOn: $understandsRisk)
                }
                HStack { Button("Cancel", role: .cancel) { dismiss() }; Spacer(); Button("Move \(model.selectedNodes.count) Items to Trash", role: .destructive) { Task { await model.moveReviewedItemsToTrash() } }.buttonStyle(.borderedProminent).tint(.red).disabled(model.selectedNodes.isEmpty || (risky && !understandsRisk)) }
            }.padding()
        }.frame(minWidth: 680, minHeight: 520)
    }
}

struct TrashResultsView: View {
    @EnvironmentObject private var model: ScanCoordinator
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Trash Results").font(.title2.bold()); Spacer(); Text("\(model.trashResults.filter(\.succeeded).count) succeeded, \(model.trashResults.filter { !$0.succeeded }.count) failed").foregroundStyle(.secondary) }.padding()
            Divider()
            List(model.trashResults) { result in
                HStack(alignment: .top) {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(result.succeeded ? .green : .red)
                    VStack(alignment: .leading, spacing: 4) { Text(result.originalURL.path).font(.callout.monospaced()).textSelection(.enabled); if let error = result.errorDescription { Text(error).foregroundStyle(.red) } else { Text("Moved to Finder Trash").foregroundStyle(.secondary) } }
                }.padding(.vertical, 3)
            }
            HStack { Text("The existing results were updated in place and volume capacity was refreshed.").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }.frame(minWidth: 650, minHeight: 420)
    }
}
