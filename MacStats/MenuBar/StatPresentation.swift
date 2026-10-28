import AppKit
import Foundation

/// Shared formatting for menu bar items — used by the real status items and
/// by the live previews in Settings.
@MainActor
enum StatPresentation {
    static func isAvailable(_ stat: MenuBarStat, store: StatsStore) -> Bool {
        switch stat {
        case .fan: return store.sensorsSampler.fanCount > 0
        case .temperature: return store.sensorsSampler.hasTemperatures
        case .battery: return store.batterySampler.hasBattery
        default: return true
        }
    }

    /// First SF Symbol name that exists on this system; battery is dynamic.
    static func symbolName(for stat: MenuBarStat, store: StatsStore) -> String {
        if stat == .battery, let battery = store.latestBattery {
            return batterySymbol(for: battery)
        }
        for name in stat.symbolCandidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "questionmark"
    }

    /// Single-line value text (network uses `networkLines` instead).
    static func title(for stat: MenuBarStat, store: StatsStore, settings: AppSettings) -> String {
        switch stat {
        case .cpu:
            return store.latestCPU.map { String(format: "%.0f%%", $0.totalUsage * 100) } ?? "--"
        case .memory:
            return memoryTitle(store: store, settings: settings)
        case .fan:
            return store.latestSensors?.fanRPM.max().map { String(format: "%.0f", $0) } ?? "--"
        case .temperature:
            return store.latestSensors?.cpuTemperature.map { String(format: "%.0f°", $0) } ?? "--"
        case .network:
            let lines = networkLines(store: store)
            return "\(lines.down) \(lines.up)"
        case .disk:
            return store.latestDisk.map { ByteFormat.diskGigabytes($0.freeBytes) } ?? "--"
        case .gpu:
            return store.latestGPU.map { String(format: "%.0f%%", $0.utilization * 100) } ?? "--"
        case .battery:
            return store.latestBattery.map { String(format: "%.0f%%", $0.level * 100) } ?? "--"
        case .bluetooth:
            return "\(store.bluetoothDevices.filter(\.isConnected).count)"
        case .awake:
            return UptimeSampler.format(store.uptime.awake)
        }
    }

    static func networkLines(store: StatsStore) -> (down: String, up: String) {
        let down = store.latestNetwork.map { ByteFormat.rate($0.downBytesPerSec) } ?? "--"
        let up = store.latestNetwork.map { ByteFormat.rate($0.upBytesPerSec) } ?? "--"
        return ("↓ \(down)", "↑ \(up)")
    }

    static func memoryTitle(store: StatsStore, settings: AppSettings) -> String {
        guard let memory = store.latestMemory else { return "--" }
        var parts: [String] = []
        if settings.memoryShowPercent {
            parts.append(String(format: "%.0f%%", memory.usedFraction * 100))
        }
        if settings.memoryShowGB {
            let bytes = settings.memoryGBMode == .used ? memory.used : memory.available
            parts.append(ByteFormat.gigabytes(bytes))
        }
        if parts.isEmpty {
            parts.append(String(format: "%.0f%%", memory.usedFraction * 100))
        }
        return parts.joined(separator: " · ")
    }

    /// Widest plausible title, used to give status items a fixed width so
    /// they don't shift as values change.
    static func templateTitle(for stat: MenuBarStat, settings: AppSettings) -> String {
        switch stat {
        case .cpu, .gpu, .battery: return "100%"
        case .memory:
            var parts: [String] = []
            if settings.memoryShowPercent { parts.append("100%") }
            if settings.memoryShowGB { parts.append("99.9 GB") }
            if parts.isEmpty { parts.append("100%") }
            return parts.joined(separator: " · ")
        case .fan: return "9999"
        case .temperature: return "100°"
        case .network: return "↓ 99.9 MB/s"
        case .disk: return "9999 GB"
        case .bluetooth: return "99"
        case .awake: return "99h 59m"
        }
    }

    static func batterySymbol(for battery: BatterySnapshot) -> String {
        if battery.isCharging { return "battery.100percent.bolt" }
        if battery.onACPower { return "powerplug" }
        switch battery.level {
        case ..<0.125: return "battery.0percent"
        case ..<0.375: return "battery.25percent"
        case ..<0.625: return "battery.50percent"
        case ..<0.875: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
