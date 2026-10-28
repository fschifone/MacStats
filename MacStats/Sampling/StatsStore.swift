import Foundation

struct HistoryPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var latestCPU: CPUSnapshot?
    @Published private(set) var cpuHistory: [HistoryPoint] = []
    @Published private(set) var latestMemory: MemorySnapshot?
    @Published private(set) var memoryHistory: [HistoryPoint] = []
    @Published private(set) var latestNetwork: NetworkSnapshot?
    @Published private(set) var networkDownHistory: [HistoryPoint] = []
    @Published private(set) var networkUpHistory: [HistoryPoint] = []
    @Published private(set) var latestDisk: DiskSnapshot?
    @Published private(set) var latestSensors: SensorsSnapshot?
    @Published private(set) var cpuTempHistory: [HistoryPoint] = []
    @Published private(set) var latestGPU: GPUSnapshot?
    @Published private(set) var gpuHistory: [HistoryPoint] = []
    @Published private(set) var latestBattery: BatterySnapshot?
    @Published private(set) var batteryHistory: [HistoryPoint] = []
    @Published private(set) var bluetoothDevices: [BluetoothDeviceInfo] = []
    @Published private(set) var uptime: UptimeSnapshot = UptimeSampler.sample()

    let cpuSampler = CPUSampler()
    let memorySampler = MemorySampler()
    let networkSampler = NetworkSampler()
    let diskSampler = DiskSampler()
    let sensorsSampler = SensorsSampler()
    let gpuSampler = GPUSampler()
    let batterySampler = BatterySampler()
    let bluetoothSampler = BluetoothSampler()
    private var timer: Timer?

    /// Fired after each sampling tick so AppKit (status items) can refresh.
    var onUpdate: (() -> Void)?

    func start() {
        guard timer == nil else { return }
        tick()
        scheduleTimer()
    }

    /// Call after AppSettings.refreshInterval changes.
    func restartTimer() {
        timer?.invalidate()
        timer = nil
        scheduleTimer()
    }

    private func scheduleTimer() {
        let timer = Timer(timeInterval: AppSettings.shared.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common keeps sampling alive while menus/popovers are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        if let snapshot = cpuSampler.sample() {
            latestCPU = snapshot
            append(&cpuHistory, value: snapshot.totalUsage)
        }
        if let snapshot = memorySampler.sample() {
            latestMemory = snapshot
            append(&memoryHistory, value: snapshot.usedFraction)
        }
        if let snapshot = networkSampler.sample() {
            latestNetwork = snapshot
            append(&networkDownHistory, value: snapshot.downBytesPerSec)
            append(&networkUpHistory, value: snapshot.upBytesPerSec)
        }
        latestDisk = diskSampler.sample()
        if let snapshot = sensorsSampler.sample() {
            latestSensors = snapshot
            if let temp = snapshot.cpuTemperature {
                append(&cpuTempHistory, value: temp)
            }
        }
        if let snapshot = gpuSampler.sample() {
            latestGPU = snapshot
            append(&gpuHistory, value: snapshot.utilization)
        }
        latestBattery = batterySampler.sample()
        if let battery = latestBattery {
            appendBatteryPoint(level: battery.level)
        }
        bluetoothDevices = bluetoothSampler.sample()
        uptime = UptimeSampler.sample()
        onUpdate?()
    }

    /// Battery drains slowly, so its history is downsampled to one point
    /// every 30 s and retained for 24 h (for the 1h/12h/24h graph windows).
    private static let batteryHistoryInterval: TimeInterval = 30
    private static let batteryHistoryLength = Int(24 * 3600 / batteryHistoryInterval)

    private func appendBatteryPoint(level: Double) {
        if let last = batteryHistory.last,
           Date().timeIntervalSince(last.date) < Self.batteryHistoryInterval {
            return
        }
        batteryHistory.append(HistoryPoint(date: Date(), value: level))
        if batteryHistory.count > Self.batteryHistoryLength {
            batteryHistory.removeFirst(batteryHistory.count - Self.batteryHistoryLength)
        }
    }

    private func append(_ history: inout [HistoryPoint], value: Double) {
        history.append(HistoryPoint(date: Date(), value: value))
        let cutoff = Date().addingTimeInterval(-Double(AppSettings.shared.graphHistoryMinutes) * 60)
        while let first = history.first, first.date < cutoff {
            history.removeFirst()
        }
    }
}
