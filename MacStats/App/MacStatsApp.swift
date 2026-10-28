import SwiftUI

@main
struct MacStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: MenuBarCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = StatsStore.shared
        coordinator = MenuBarCoordinator(store: store)
        store.start()
    }
}
