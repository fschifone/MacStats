import Foundation
import IOKit

struct DiskSnapshot {
    var volumeName: String
    var totalBytes: UInt64
    var freeBytes: UInt64
    var readBytesPerSec: Double
    var writeBytesPerSec: Double

    var usedBytes: UInt64 { totalBytes > freeBytes ? totalBytes - freeBytes : 0 }
    var usedFraction: Double { totalBytes > 0 ? Double(usedBytes) / Double(totalBytes) : 0 }
}

/// Free space from the root volume; read/write throughput summed over all
/// IOBlockStorageDriver instances (tick deltas).
final class DiskSampler {
    private var previousRead: UInt64?
    private var previousWrite: UInt64?
    private var previousDate: Date?

    func sample() -> DiskSnapshot? {
        let rootURL = URL(fileURLWithPath: "/")
        let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
        ])
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        let free = UInt64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let name = values?.volumeName ?? "Macintosh HD"

        let (read, write) = Self.blockStorageTotals()
        let now = Date()
        var readRate = 0.0
        var writeRate = 0.0
        if let previousRead, let previousWrite, let previousDate {
            let elapsed = now.timeIntervalSince(previousDate)
            if elapsed > 0.1, read >= previousRead, write >= previousWrite {
                readRate = Double(read - previousRead) / elapsed
                writeRate = Double(write - previousWrite) / elapsed
            }
        }
        previousRead = read
        previousWrite = write
        previousDate = now

        return DiskSnapshot(volumeName: name,
                            totalBytes: total,
                            freeBytes: free,
                            readBytesPerSec: readRate,
                            writeBytesPerSec: writeRate)
    }

    private static func blockStorageTotals() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0
        var write: UInt64 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let statsRef = IORegistryEntryCreateCFProperty(entry,
                                                                 "Statistics" as CFString,
                                                                 kCFAllocatorDefault,
                                                                 0),
                  let stats = statsRef.takeRetainedValue() as? [String: Any] else { continue }
            read += (stats["Bytes (Read)"] as? UInt64) ?? 0
            write += (stats["Bytes (Write)"] as? UInt64) ?? 0
        }
        return (read, write)
    }
}
