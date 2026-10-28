import CoreBluetooth
import Foundation
import IOBluetooth
import IOKit

struct BluetoothDeviceInfo: Identifiable {
    var name: String
    var address: String
    var isConnected: Bool
    /// 0...100 where the device reports a single level.
    var batteryPercent: Int?
    /// AirPods-style component levels, 0...100.
    var leftPercent: Int?
    var rightPercent: Int?
    var casePercent: Int?

    var id: String { address }
}

@MainActor
final class BluetoothSampler {
    private struct CachedBattery {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    private let bleReader = BLEBatteryReader()
    /// Battery info from system_profiler, keyed by normalized address.
    private var profilerBattery: [String: CachedBattery] = [:]
    private var profilerRunning = false
    private var lastProfilerRun: Date?

    func sample() -> [BluetoothDeviceInfo] {
        refreshProfilerCacheIfNeeded()
        bleReader.refreshIfNeeded()

        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }
        let hidLevels = Self.hidBatteryLevels()

        return paired.compactMap { device in
            guard let address = device.addressString else { return nil }
            let normalized = Self.normalize(address)
            let connected = device.isConnected()
            let name = device.name ?? "Unknown device"
            let cached = profilerBattery[normalized]

            var info = BluetoothDeviceInfo(name: name,
                                           address: normalized,
                                           isConnected: connected)
            // Battery is only meaningful while connected.
            if connected {
                info.batteryPercent = hidLevels[normalized]
                    ?? cached?.main
                    ?? bleReader.levelsByName[name]
                info.leftPercent = cached?.left
                info.rightPercent = cached?.right
                info.casePercent = cached?.caseLevel
            }
            return info
        }
        .sorted { ($0.isConnected ? 0 : 1, $0.name) < ($1.isConnected ? 0 : 1, $1.name) }
    }

    // MARK: - system_profiler cache (AirPods and friends)

    private func refreshProfilerCacheIfNeeded() {
        if let last = lastProfilerRun, Date().timeIntervalSince(last) < 60 { return }
        guard !profilerRunning else { return }
        profilerRunning = true
        lastProfilerRun = Date()

        Task.detached(priority: .utility) {
            let parsed = Self.runProfiler()
            await MainActor.run { [weak self] in
                self?.profilerBattery = parsed
                self?.profilerRunning = false
            }
        }
    }

    nonisolated private static func runProfiler() -> [String: CachedBattery] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }

        var result: [String: CachedBattery] = [:]
        for section in sections {
            for listKey in ["device_connected", "device_not_connected"] {
                guard let devices = section[listKey] as? [[String: Any]] else { continue }
                for entry in devices {
                    for (_, value) in entry {
                        guard let properties = value as? [String: Any],
                              let address = properties["device_address"] as? String else { continue }
                        var battery = CachedBattery()
                        battery.main = Self.percent(properties["device_batteryLevelMain"])
                        battery.left = Self.percent(properties["device_batteryLevelLeft"])
                        battery.right = Self.percent(properties["device_batteryLevelRight"])
                        battery.caseLevel = Self.percent(properties["device_batteryLevelCase"])
                        if battery.main != nil || battery.left != nil
                            || battery.right != nil || battery.caseLevel != nil {
                            result[normalize(address)] = battery
                        }
                    }
                }
            }
        }
        return result
    }

    nonisolated private static func percent(_ value: Any?) -> Int? {
        guard let string = value as? String else { return nil }
        return Int(string.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
    }

    // MARK: - HID registry (Apple Magic accessories)

    private static func hidBatteryLevels() -> [String: Int] {
        var levels: [String: Int] = [:]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                           &iterator) == KERN_SUCCESS else { return levels }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let percentRef = IORegistryEntryCreateCFProperty(entry,
                                                                   "BatteryPercent" as CFString,
                                                                   kCFAllocatorDefault, 0),
                  let percent = percentRef.takeRetainedValue() as? Int else { continue }
            guard let addressRef = IORegistryEntryCreateCFProperty(entry,
                                                                   "DeviceAddress" as CFString,
                                                                   kCFAllocatorDefault, 0),
                  let address = addressRef.takeRetainedValue() as? String else { continue }
            levels[normalize(address)] = percent
        }
        return levels
    }

    nonisolated fileprivate static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: "-", with: ":")
    }
}

/// Reads the standard GATT Battery Service (0x180F, characteristic 0x2A19)
/// from BLE peripherals the system is already connected to — this is how
/// third-party BLE mice and keyboards (Logitech MX etc.) report battery.
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")

    private var central: CBCentralManager!
    private var trackedPeripherals: [UUID: CBPeripheral] = [:]
    private var lastRefresh: Date?

    /// Levels keyed by peripheral name (CoreBluetooth has no MAC address).
    private(set) var levelsByName: [String: Int] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func refreshIfNeeded() {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 60 { return }
        guard central.state == .poweredOn else { return }
        lastRefresh = Date()

        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        for peripheral in connected {
            trackedPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            if peripheral.state != .connected {
                central.connect(peripheral)
            } else {
                peripheral.discoverServices([Self.batteryService])
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            lastRefresh = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristic = service.characteristics?
            .first(where: { $0.uuid == Self.batteryLevelCharacteristic }) else { return }
        peripheral.readValue(for: characteristic)
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.batteryLevelCharacteristic,
              let byte = characteristic.value?.first,
              let name = peripheral.name else { return }
        levelsByName[name] = Int(byte)
    }
}
