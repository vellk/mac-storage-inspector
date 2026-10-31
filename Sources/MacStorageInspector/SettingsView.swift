import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: ScanCoordinator
    @State private var newPath = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Excluded Folders").font(.title2.bold())
            Text("Exact paths listed here are skipped and reported as exclusions. Symlinks and other filesystems are always excluded from traversal by default.").foregroundStyle(.secondary)
            List { ForEach(model.excludedPaths, id: \.self) { Text($0).font(.callout.monospaced()).textSelection(.enabled) }.onDelete(perform: model.removeExclusions) }
            HStack { TextField("/absolute/path/to/exclude", text: $newPath); Button("Add") { guard newPath.hasPrefix("/") else { model.errorMessage = "Enter an absolute path beginning with /."; return }; model.addExclusion(newPath); newPath = "" }.disabled(newPath.isEmpty) }
            Text("Settings are stored locally. Mac Storage Inspector has no networking, analytics, or background service.").font(.caption).foregroundStyle(.secondary)
        }.padding()
    }
}
