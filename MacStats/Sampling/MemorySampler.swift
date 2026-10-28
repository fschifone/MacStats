import Darwin
import Foundation

struct MemorySnapshot {
    var total: UInt64
    var appMemory: UInt64
    var wired: UInt64
    var compressed: UInt64
    var free: UInt64
    /// File-backed plus purgeable pages, Activity Monitor's "Cached Files".
    var cachedFiles: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    /// 1 = normal, 2 = warning, 4 = critical (kern.memorystatus_vm_pressure_level).
    var pressureLevel: Int

    var used: UInt64 { appMemory + wired + compressed }
    var available: UInt64 { total > used ? total - used : 0 }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    var pressureLabel: String {
        switch pressureLevel {
        case 4: return "Critical"
        case 2: return "Warning"
        default: return "OK"
        }
    }
}

final class MemorySampler {
    private let totalMemory: UInt64
    private let pageSize: UInt64

    init() {
        var size = MemoryLayout<UInt64>.size
        var memsize: UInt64 = 0
        sysctlbyname("hw.memsize", &memsize, &size, nil, 0)
        totalMemory = memsize

        var hostPageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &hostPageSize)
        pageSize = UInt64(hostPageSize)
    }

    func sample() -> MemorySnapshot? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // "App memory" the way Activity Monitor counts it: anonymous pages
        // minus purgeable ones.
        let internalPages = UInt64(stats.internal_page_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : 0

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var pressure: Int32 = 1
        var pressureSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0)

        return MemorySnapshot(total: totalMemory,
                              appMemory: appPages * pageSize,
                              wired: UInt64(stats.wire_count) * pageSize,
                              compressed: UInt64(stats.compressor_page_count) * pageSize,
                              free: UInt64(stats.free_count) * pageSize,
                              cachedFiles: (UInt64(stats.external_page_count) + purgeablePages) * pageSize,
                              swapUsed: swap.xsu_used,
                              swapTotal: swap.xsu_total,
                              pressureLevel: Int(pressure))
    }
}

enum ByteFormat {
    /// Binary gigabytes with one decimal, e.g. "14.9 GB".
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    /// Decimal gigabytes (what Finder shows for disks), e.g. "412 GB".
    static func diskGigabytes(_ bytes: UInt64) -> String {
        String(format: "%.0f GB", Double(bytes) / 1_000_000_000)
    }

    /// Adaptive throughput, e.g. "890 KB/s" or "4.2 MB/s".
    static func rate(_ bytesPerSec: Double) -> String {
        switch bytesPerSec {
        case ..<1024: return String(format: "%.0f B/s", bytesPerSec)
        case ..<1_048_576: return String(format: "%.0f KB/s", bytesPerSec / 1024)
        default: return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        }
    }
}
