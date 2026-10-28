import Foundation
import IOKit

struct GPUSnapshot {
    /// 0...1
    var utilization: Double
}

/// GPU utilization from the IOAccelerator "PerformanceStatistics" property.
/// This is undocumented but long-stable; on Apple Silicon the AGXAccelerator
/// service publishes "Device Utilization %".
final class GPUSampler {
    func sample() -> GPUSnapshot? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let statsRef = IORegistryEntryCreateCFProperty(entry,
                                                                 "PerformanceStatistics" as CFString,
                                                                 kCFAllocatorDefault,
                                                                 0),
                  let stats = statsRef.takeRetainedValue() as? [String: Any] else { continue }
            if let utilization = stats["Device Utilization %"] as? Int {
                return GPUSnapshot(utilization: Double(utilization) / 100)
            }
        }
        return nil
    }
}
