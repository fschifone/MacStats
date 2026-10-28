import Darwin
import Foundation

struct UptimeSnapshot {
    /// Time the machine has been awake (pauses during sleep).
    var awake: TimeInterval
    /// Wall-clock time since boot.
    var uptime: TimeInterval
}

enum UptimeSampler {
    static func sample() -> UptimeSnapshot {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        var uptime: TimeInterval = 0
        if sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0, bootTime.tv_sec > 0 {
            uptime = Date().timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(bootTime.tv_sec)))
        }
        // systemUptime is mach_absolute_time based and stops during sleep.
        return UptimeSnapshot(awake: ProcessInfo.processInfo.systemUptime,
                              uptime: uptime)
    }

    /// "3h 12m", "2d 5h", "48m".
    static func format(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}
