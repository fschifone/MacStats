import Darwin
import Foundation

struct CPUSnapshot {
    /// All fractions are 0...1.
    var totalUsage: Double
    var userUsage: Double
    var systemUsage: Double
    var perCoreUsage: [Double]
    var loadAverage: Double
}

/// Samples per-core CPU usage via `host_processor_info`. Usage is computed
/// from tick deltas between consecutive calls, so the first call returns nil.
final class CPUSampler {
    private struct Ticks {
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        var busy: UInt64 { user + system + nice }
        var total: UInt64 { busy + idle }
    }

    private var previous: [Ticks] = []

    /// On Apple Silicon, perflevel0 is the performance cluster and
    /// perflevel1 the efficiency cluster.
    let performanceCoreCount: Int
    let efficiencyCoreCount: Int

    init() {
        performanceCoreCount = Self.sysctlInt("hw.perflevel0.logicalcpu")
        efficiencyCoreCount = Self.sysctlInt("hw.perflevel1.logicalcpu")
    }

    func sample() -> CPUSnapshot? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(),
                                  PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount,
                                  &infoArray,
                                  &infoCount) == KERN_SUCCESS,
              let info = infoArray else { return nil }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        var current: [Ticks] = []
        current.reserveCapacity(Int(cpuCount))
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            var t = Ticks()
            t.user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            t.system = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            t.idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            t.nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            current.append(t)
        }

        defer { previous = current }
        guard previous.count == current.count else { return nil }

        var perCore: [Double] = []
        var busySum = 0.0, totalSum = 0.0, userSum = 0.0, systemSum = 0.0
        for (prev, cur) in zip(previous, current) {
            // Tick counters are 32-bit and wrap; skip a core on wraparound.
            guard cur.total >= prev.total, cur.busy >= prev.busy else {
                perCore.append(0)
                continue
            }
            let total = Double(cur.total - prev.total)
            let busy = Double(cur.busy - prev.busy)
            perCore.append(total > 0 ? busy / total : 0)
            busySum += busy
            totalSum += total
            userSum += Double((cur.user + cur.nice) - (prev.user + prev.nice))
            systemSum += Double(cur.system - prev.system)
        }
        guard totalSum > 0 else { return nil }

        var load = [Double](repeating: 0, count: 1)
        getloadavg(&load, 1)

        return CPUSnapshot(totalUsage: busySum / totalSum,
                           userUsage: userSum / totalSum,
                           systemUsage: systemSum / totalSum,
                           perCoreUsage: perCore,
                           loadAverage: load[0])
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }
}
