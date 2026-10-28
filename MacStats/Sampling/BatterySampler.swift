import Foundation
import IOKit
import IOKit.ps

struct BatterySnapshot {
    /// 0...1
    var level: Double
    var isCharging: Bool
    var onACPower: Bool
    /// Minutes to empty (on battery) or to full (charging); nil when unknown.
    var minutesRemaining: Int?
    var cycleCount: Int?
    /// 0...1, current max capacity vs design capacity.
    var health: Double?

    var stateLabel: String {
        if isCharging { return "Charging" }
        if onACPower { return "On AC power" }
        return "On battery"
    }
}

final class BatterySampler {
    /// False on desktops; checked once at startup.
    let hasBattery: Bool

    init() {
        hasBattery = Self.internalBatteryDescription() != nil
    }

    func sample() -> BatterySnapshot? {
        guard hasBattery, let description = Self.internalBatteryDescription() else { return nil }

        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        var minutes: Int?
        let timeKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        if let time = description[timeKey] as? Int, time > 0 {
            minutes = time
        }

        var cycles: Int?
        var health: Double?
        if let battery = Self.smartBatteryProperties() {
            cycles = battery["CycleCount"] as? Int
            let maxCapacity = (battery["AppleRawMaxCapacity"] as? Int)
                ?? (battery["NominalChargeCapacity"] as? Int)
            if let maxCapacity, let design = battery["DesignCapacity"] as? Int, design > 0 {
                health = Double(maxCapacity) / Double(design)
            }
        }

        return BatterySnapshot(level: max > 0 ? Double(current) / Double(max) : 0,
                               isCharging: isCharging,
                               onACPower: onAC,
                               minutesRemaining: minutes,
                               cycleCount: cycles,
                               health: health)
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let infoRef = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(infoRef)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(infoRef, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                return description
            }
        }
        return nil
    }

    private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var propertiesRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propertiesRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = propertiesRef?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return properties
    }
}
