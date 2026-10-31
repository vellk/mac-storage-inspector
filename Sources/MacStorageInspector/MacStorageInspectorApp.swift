import SwiftUI

@main
struct MacStorageInspectorApp: App {
    @StateObject private var coordinator = ScanCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(coordinator)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environmentObject(coordinator)
                .frame(width: 560, height: 360)
        }
    }
}
