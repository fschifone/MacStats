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
        // Tighten the gaps between this app's status items to system-item
        // density (read by AppKit when the items are created).
        UserDefaults.standard.register(defaults: [
            "NSStatusItemSpacing": 6,
            "NSStatusItemSelectionPadding": 8,
        ])
        let store = StatsStore.shared
        coordinator = MenuBarCoordinator(store: store)
        store.start()
    }
}
