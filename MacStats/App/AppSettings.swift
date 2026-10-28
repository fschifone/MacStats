import Foundation

enum MemoryGBMode: String {
    case used
    case available
}

/// Every stat that can be its own menu bar item.
enum MenuBarStat: String, CaseIterable, Identifiable {
    case cpu, memory, fan, temperature, network, disk, gpu, battery, bluetooth, awake

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .fan: return "Fan speed"
        case .temperature: return "Temperature"
        case .network: return "Network"
        case .disk: return "Disk"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .bluetooth: return "Bluetooth"
        case .awake: return "Time awake"
        }
    }

    /// SF Symbol candidates, first available wins.
    var symbolCandidates: [String] {
        switch self {
        case .cpu: return ["cpu"]
        case .memory: return ["memorychip"]
        case .fan: return ["fanblades", "fan"]
        case .temperature: return ["thermometer.medium", "thermometer"]
        case .network: return ["arrow.up.arrow.down"]
        case .disk: return ["internaldrive"]
        case .gpu: return ["gpu", "cpu.fill"]
        case .bluetooth: return ["antenna.radiowaves.left.and.right"]
        case .battery: return ["battery.100percent", "battery.100"]
        case .awake: return ["clock"]
        }
    }
}

/// Sections of the popover, in user-configurable order.
enum PopoverSection: String, CaseIterable, Identifiable {
    case cpu, memory, sensors, network, disk, gpu, battery, bluetooth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .sensors: return "Fans & Temperatures"
        case .network: return "Network"
        case .disk: return "Disk"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        case .bluetooth: return "Bluetooth"
        }
    }
}

/// User preferences, persisted in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var memoryShowPercent: Bool {
        didSet { defaults.set(memoryShowPercent, forKey: "memoryShowPercent") }
    }
    @Published var memoryShowGB: Bool {
        didSet { defaults.set(memoryShowGB, forKey: "memoryShowGB") }
    }
    @Published var memoryGBMode: MemoryGBMode {
        didSet { defaults.set(memoryGBMode.rawValue, forKey: "memoryGBMode") }
    }
    /// Battery graph window in hours: 1, 12 or 24.
    @Published var batteryGraphHours: Int {
        didSet { defaults.set(batteryGraphHours, forKey: "batteryGraphHours") }
    }
    /// Raw values of the MenuBarStat cases shown in the menu bar.
    @Published var menuBarStats: Set<String> {
        didSet { defaults.set(Array(menuBarStats), forKey: "menuBarStats") }
    }
    /// All PopoverSection raw values, in display order.
    @Published var popoverOrder: [String] {
        didSet { defaults.set(popoverOrder, forKey: "popoverOrder") }
    }
    /// Raw values of the sections shown in the popover.
    @Published var popoverEnabled: Set<String> {
        didSet { defaults.set(Array(popoverEnabled), forKey: "popoverEnabled") }
    }
    /// Sampling interval in seconds: 1, 2 or 5.
    @Published var refreshInterval: Double {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval") }
    }
    /// Window of the usage graphs in minutes: 5, 10 or 30.
    @Published var graphHistoryMinutes: Int {
        didSet { defaults.set(graphHistoryMinutes, forKey: "graphHistoryMinutes") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "memoryShowPercent": true,
            "memoryShowGB": true,
            "memoryGBMode": MemoryGBMode.used.rawValue,
            "batteryGraphHours": 1,
        ])
        memoryShowPercent = defaults.bool(forKey: "memoryShowPercent")
        memoryShowGB = defaults.bool(forKey: "memoryShowGB")
        memoryGBMode = MemoryGBMode(rawValue: defaults.string(forKey: "memoryGBMode") ?? "") ?? .used
        let hours = defaults.integer(forKey: "batteryGraphHours")
        batteryGraphHours = [1, 12, 24].contains(hours) ? hours : 1

        let validStats = Set(MenuBarStat.allCases.map(\.rawValue))
        if let stored = defaults.stringArray(forKey: "menuBarStats") {
            menuBarStats = Set(stored).intersection(validStats)
        } else {
            menuBarStats = [MenuBarStat.cpu, .memory, .fan, .temperature, .network, .battery]
                .reduce(into: []) { $0.insert($1.rawValue) }
        }

        let allSections = PopoverSection.allCases.map(\.rawValue)
        var order = (defaults.stringArray(forKey: "popoverOrder") ?? allSections)
            .filter { allSections.contains($0) }
        for section in allSections where !order.contains(section) {
            order.append(section)
        }
        popoverOrder = order

        if let stored = defaults.stringArray(forKey: "popoverEnabled") {
            popoverEnabled = Set(stored).intersection(Set(allSections))
        } else {
            popoverEnabled = Set(allSections)
        }

        let interval = defaults.double(forKey: "refreshInterval")
        refreshInterval = [1.0, 2.0, 5.0].contains(interval) ? interval : 2.0
        let minutes = defaults.integer(forKey: "graphHistoryMinutes")
        graphHistoryMinutes = [5, 10, 30].contains(minutes) ? minutes : 10
    }
}
