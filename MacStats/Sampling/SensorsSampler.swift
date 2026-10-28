import Foundation

struct SensorsSnapshot {
    /// RPM per fan, empty on fanless machines.
    var fanRPM: [Double]
    var cpuTemperature: Double?
    var gpuTemperature: Double?
}

/// Fan speeds and die temperatures via the SMC.
///
/// Apple Silicon exposes temperature sensors under model-specific keys, so
/// instead of a hardcoded list we enumerate all keys once and keep those that
/// look like CPU ("Tp*") and GPU ("Tg*") temperature sensors, then average
/// the plausible readings each tick.
final class SensorsSampler {
    private let smc: SMCClient?
    private let cpuTempKeys: [String]
    private let gpuTempKeys: [String]
    let fanCount: Int

    var hasTemperatures: Bool { !cpuTempKeys.isEmpty || !gpuTempKeys.isEmpty }

    init() {
        smc = SMCClient()
        guard let smc else {
            cpuTempKeys = []
            gpuTempKeys = []
            fanCount = 0
            return
        }

        var cpuKeys: [String] = []
        var gpuKeys: [String] = []
        for index in 0..<smc.keyCount {
            guard let key = smc.key(atIndex: index) else { continue }
            if key.hasPrefix("Tp") {
                cpuKeys.append(key)
            } else if key.hasPrefix("Tg") {
                gpuKeys.append(key)
            }
        }
        // Keep only keys that currently return a plausible temperature.
        cpuTempKeys = cpuKeys.filter { Self.plausibleTemperature(smc.read(key: $0)?.doubleValue) }
        gpuTempKeys = gpuKeys.filter { Self.plausibleTemperature(smc.read(key: $0)?.doubleValue) }

        if let value = smc.read(key: "FNum")?.doubleValue {
            fanCount = Int(value)
        } else {
            fanCount = 0
        }
    }

    func sample() -> SensorsSnapshot? {
        guard let smc else { return nil }

        var fans: [Double] = []
        for fan in 0..<fanCount {
            if let rpm = smc.read(key: "F\(fan)Ac")?.doubleValue, rpm >= 0, rpm < 20000 {
                fans.append(rpm)
            }
        }

        return SensorsSnapshot(fanRPM: fans,
                               cpuTemperature: average(of: cpuTempKeys, from: smc),
                               gpuTemperature: average(of: gpuTempKeys, from: smc))
    }

    private func average(of keys: [String], from smc: SMCClient) -> Double? {
        let values = keys.compactMap { key -> Double? in
            let value = smc.read(key: key)?.doubleValue
            return Self.plausibleTemperature(value) ? value : nil
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func plausibleTemperature(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value > 10 && value < 120
    }
}
