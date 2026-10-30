import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            MenuBarSettingsTab()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            PopoverSettingsTab()
                .tabItem { Label("Popover", systemImage: "rectangle.bottomthird.inset.filled") }
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 480)
    }
}

// MARK: - Menu Bar tab

private struct MenuBarSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = StatsStore.shared

    var body: some View {
        Form {
            Section("Show in menu bar") {
                ForEach(MenuBarStat.allCases) { stat in
                    HStack(spacing: 10) {
                        Toggle(isOn: menuBarBinding(stat)) {
                            Text(stat.label)
                                .frame(width: 110, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!StatPresentation.isAvailable(stat, store: store))
                        MenuBarItemPreview(stat: stat, store: store)
                        Spacer()
                    }
                }
            }

            Section("Memory item") {
                HStack(spacing: 14) {
                    Toggle("Percentage", isOn: $settings.memoryShowPercent)
                        .toggleStyle(.checkbox)
                    Toggle("GB", isOn: $settings.memoryShowGB)
                        .toggleStyle(.checkbox)
                    Picker("", selection: $settings.memoryGBMode) {
                        Text("Used").tag(MemoryGBMode.used)
                        Text("Available").tag(MemoryGBMode.available)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!settings.memoryShowGB)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func menuBarBinding(_ stat: MenuBarStat) -> Binding<Bool> {
        Binding(
            get: { settings.menuBarStats.contains(stat.rawValue) },
            set: { enabled in
                if enabled {
                    settings.menuBarStats.insert(stat.rawValue)
                } else {
                    settings.menuBarStats.remove(stat.rawValue)
                }
            }
        )
    }
}

// MARK: - Popover tab

private struct PopoverSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var store = StatsStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(settings.popoverOrder, id: \.self) { raw in
                    if let section = PopoverSection(rawValue: raw) {
                        HStack(spacing: 10) {
                            Toggle(isOn: popoverBinding(section)) {
                                Text(section.label)
                                    .frame(width: 140, alignment: .leading)
                            }
                            .toggleStyle(.checkbox)
                            PopoverSectionPreview(section: section, store: store)
                            Spacer()
                            Button {
                                move(raw, by: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(settings.popoverOrder.first == raw)
                            Button {
                                move(raw, by: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(settings.popoverOrder.last == raw)
                        }
                    }
                }
            } header: {
                Text("Popover sections")
            } footer: {
                Text("Use the arrows to change the order in the popover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func popoverBinding(_ section: PopoverSection) -> Binding<Bool> {
        Binding(
            get: { settings.popoverEnabled.contains(section.rawValue) },
            set: { enabled in
                if enabled {
                    settings.popoverEnabled.insert(section.rawValue)
                } else {
                    settings.popoverEnabled.remove(section.rawValue)
                }
            }
        )
    }

    private func move(_ raw: String, by delta: Int) {
        guard let index = settings.popoverOrder.firstIndex(of: raw) else { return }
        let target = index + delta
        guard settings.popoverOrder.indices.contains(target) else { return }
        settings.popoverOrder.swapAt(index, target)
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Sampling") {
                Picker("Refresh interval", selection: $settings.refreshInterval) {
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
                .pickerStyle(.segmented)

                Picker("Graph history", selection: $settings.graphHistoryMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("30 min").tag(30)
                }
                .pickerStyle(.segmented)

                Picker("Battery graph", selection: $settings.batteryGraphHours) {
                    Text("1 h").tag(1)
                    Text("12 h").tag(12)
                    Text("24 h").tag(24)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Live previews

/// Live rendering of a menu bar item, as it looks in the menu bar right now.
struct MenuBarItemPreview: View {
    let stat: MenuBarStat
    @ObservedObject var store: StatsStore
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            if StatPresentation.isAvailable(stat, store: store) {
                HStack(spacing: 4) {
                    Image(systemName: StatPresentation.symbolName(for: stat, store: store))
                        .font(.system(size: 11))
                    if stat == .network {
                        let lines = StatPresentation.networkLines(store: store)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(lines.down)
                            Text(lines.up)
                        }
                        .font(.system(size: 7.5, weight: .medium))
                        .monospacedDigit()
                    } else {
                        Text(StatPresentation.title(for: stat, store: store, settings: settings))
                            .font(.system(size: 11))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.primary)
            } else {
                Text("not available")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// Live summary chip(s) for a popover section.
struct PopoverSectionPreview: View {
    let section: PopoverSection
    @ObservedObject var store: StatsStore

    private var stats: [MenuBarStat] {
        switch section {
        case .cpu: return [.cpu]
        case .memory: return [.memory]
        case .fans: return [.fan]
        case .temperatures: return [.temperature]
        case .network: return [.network]
        case .disk: return [.disk]
        case .gpu: return [.gpu]
        case .battery: return [.battery]
        case .bluetooth: return [.bluetooth]
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(stats.filter { StatPresentation.isAvailable($0, store: store) }) { stat in
                MenuBarItemPreview(stat: stat, store: store)
            }
        }
    }
}
