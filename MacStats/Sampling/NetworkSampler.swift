import Darwin
import Foundation

struct NetworkSnapshot {
    var downBytesPerSec: Double
    var upBytesPerSec: Double
    /// Interface carrying the most traffic this tick, e.g. "en0".
    var primaryInterface: String
}

/// Sums traffic across non-loopback interfaces via getifaddrs and converts
/// tick deltas to bytes/sec. Counters are 32-bit, so deltas use wrapping
/// subtraction.
final class NetworkSampler {
    private struct Counters {
        var inBytes: UInt32 = 0
        var outBytes: UInt32 = 0
    }

    private var previous: [String: Counters] = [:]
    private var previousDate: Date?

    func sample() -> NetworkSnapshot? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var current: [String: Counters] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let flags = Int32(ifa.pointee.ifa_flags)
            guard ifa.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  flags & IFF_UP != 0,
                  flags & IFF_LOOPBACK == 0,
                  let dataPointer = ifa.pointee.ifa_data else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            current[name] = Counters(inBytes: data.ifi_ibytes, outBytes: data.ifi_obytes)
        }

        let now = Date()
        defer {
            previous = current
            previousDate = now
        }
        guard let previousDate, !previous.isEmpty else { return nil }
        let elapsed = now.timeIntervalSince(previousDate)
        guard elapsed > 0.1 else { return nil }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primary = ""
        var primaryDelta: UInt64 = 0
        for (name, counters) in current {
            guard let prev = previous[name] else { continue }
            let deltaIn = UInt64(counters.inBytes &- prev.inBytes)
            let deltaOut = UInt64(counters.outBytes &- prev.outBytes)
            totalIn += deltaIn
            totalOut += deltaOut
            // Prefer real interfaces (en*) when picking the busiest one.
            if name.hasPrefix("en"), deltaIn + deltaOut >= primaryDelta {
                primaryDelta = deltaIn + deltaOut
                primary = name
            }
        }

        return NetworkSnapshot(downBytesPerSec: Double(totalIn) / elapsed,
                               upBytesPerSec: Double(totalOut) / elapsed,
                               primaryInterface: primary)
    }
}
