import AppKit
import Combine
import SwiftUI

/// Owns one NSStatusItem per enabled stat and the shared popover.
@MainActor
final class MenuBarCoordinator: NSObject {
    private let store: StatsStore
    private let settings = AppSettings.shared
    private let popover = NSPopover()
    private var items: [MenuBarStat: NSStatusItem] = [:]
    private var currentStats: [MenuBarStat] = []
    private var currentInterval: Double
    private var settingsSubscription: AnyCancellable?

    init(store: StatsStore) {
        self.store = store
        currentInterval = settings.refreshInterval
        super.init()

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store))

        rebuildItems()

        store.onUpdate = { [weak self] in self?.refreshTitles() }
        settingsSubscription = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.settingsChanged() }
        }
    }

    // MARK: - Item lifecycle

    private func desiredStats() -> [MenuBarStat] {
        MenuBarStat.allCases.filter {
            settings.menuBarStats.contains($0.rawValue) && StatPresentation.isAvailable($0, store: store)
        }
    }

    private func settingsChanged() {
        if desiredStats() != currentStats {
            rebuildItems()
        }
        if settings.refreshInterval != currentInterval {
            currentInterval = settings.refreshInterval
            store.restartTimer()
        }
        // The memory item's width depends on its display options.
        for (stat, item) in items {
            item.length = fixedLength(for: stat)
        }
        refreshTitles()
    }

    /// Status items are inserted right-to-left, so rebuilding everything in
    /// reverse keeps the configured display order stable.
    private func rebuildItems() {
        for (_, item) in items {
            NSStatusBar.system.removeStatusItem(item)
        }
        items = [:]
        currentStats = desiredStats()
        for stat in currentStats.reversed() {
            items[stat] = makeStatusItem(for: stat)
        }
        refreshTitles()
    }

    private func makeStatusItem(for stat: MenuBarStat) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: fixedLength(for: stat))
        if let button = item.button {
            button.image = Self.symbolImage(candidates: stat.symbolCandidates, description: stat.label)
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.title = " --"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        return item
    }

    /// Fixed item width: icon plus the widest plausible value, so items don't
    /// shift as values change.
    private func fixedLength(for stat: MenuBarStat) -> CGFloat {
        let font = stat == .network
            ? NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
            : NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let template = " " + StatPresentation.templateTitle(for: stat, settings: settings)
        let textWidth = (template as NSString).size(withAttributes: [.font: font]).width
        let imageWidth: CGFloat = stat == .battery ? 22 : 16
        return ceil(textWidth + imageWidth + 2)
    }

    private static func symbolImage(candidates: [String], description: String) -> NSImage? {
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: description) {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    // MARK: - Titles

    private func refreshTitles() {
        for (stat, item) in items {
            guard let button = item.button else { continue }
            switch stat {
            case .network:
                let lines = StatPresentation.networkLines(store: store)
                button.attributedTitle = Self.twoLineTitle(top: lines.down, bottom: lines.up)
            case .battery:
                button.title = " " + StatPresentation.title(for: stat, store: store, settings: settings)
                button.image = Self.symbolImage(candidates: [StatPresentation.symbolName(for: stat, store: store)],
                                                description: "Battery level")
            default:
                button.title = " " + StatPresentation.title(for: stat, store: store, settings: settings)
            }
        }
    }

    /// Compact stacked two-line title for a status item (iStat style).
    private static func twoLineTitle(top: String, bottom: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 9
        paragraph.maximumLineHeight = 9
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium),
            .paragraphStyle: paragraph,
            .baselineOffset: -4,
        ]
        return NSAttributedString(string: " \(top)\n \(bottom)", attributes: attributes)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }
}
