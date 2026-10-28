import Foundation
import IOKit

/// Minimal AppleSMC user client, enough to enumerate keys and read values.
/// Layout and selectors follow the well-known SMCParamStruct ABI used by
/// SMCKit, smctemp, Stats, etc.
final class SMCClient {
    private struct SMCVersion {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpuPLimit: UInt32 = 0, gpuPLimit: UInt32 = 0, memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        // Swift lays out nested structs by size (9 bytes), C by stride (12):
        // this padding realigns `result` to the C offset 40 and `data8` to 42.
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Selector: UInt8 {
        case readKey = 5
        case getKeyFromIndex = 8
        case getKeyInfo = 9
    }

    struct Value {
        var bytes: [UInt8]
        var dataType: String

        /// Best-effort numeric decoding of the common SMC data types.
        var doubleValue: Double? {
            switch dataType {
            case "flt ":
                guard bytes.count >= 4 else { return nil }
                return Double(bytes.withUnsafeBytes { $0.loadUnaligned(as: Float32.self) })
            case "sp78":
                guard bytes.count >= 2 else { return nil }
                let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
                return Double(raw) / 256
            case "fpe2":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
            case "ui8 ":
                return bytes.first.map(Double.init)
            case "ui16":
                guard bytes.count >= 2 else { return nil }
                return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            case "ui32":
                guard bytes.count >= 4 else { return nil }
                return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                              | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
            default:
                return nil
            }
        }
    }

    private let connection: io_connect_t

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
        self.connection = connection
    }

    deinit {
        IOServiceClose(connection)
    }

    private func call(_ input: inout SMCParamStruct) -> SMCParamStruct? {
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let result = IOConnectCallStructMethod(connection,
                                               2, // kSMCHandleYPCEvent
                                               &input,
                                               MemoryLayout<SMCParamStruct>.stride,
                                               &output,
                                               &outputSize)
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    var keyCount: Int {
        guard let value = read(key: "#KEY"), let count = value.doubleValue else { return 0 }
        return Int(count)
    }

    func key(atIndex index: Int) -> String? {
        var input = SMCParamStruct()
        input.data8 = Selector.getKeyFromIndex.rawValue
        input.data32 = UInt32(index)
        guard let output = call(&input) else { return nil }
        return Self.fourCC(output.key)
    }

    func read(key: String) -> Value? {
        guard let code = Self.code(for: key) else { return nil }

        var infoInput = SMCParamStruct()
        infoInput.key = code
        infoInput.data8 = Selector.getKeyInfo.rawValue
        guard let info = call(&infoInput) else { return nil }
        let size = Int(info.keyInfo.dataSize)
        guard size > 0, size <= 32 else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = code
        readInput.keyInfo.dataSize = info.keyInfo.dataSize
        readInput.data8 = Selector.readKey.rawValue
        guard let output = call(&readInput) else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(size)) }
        return Value(bytes: bytes, dataType: Self.fourCC(info.keyInfo.dataType))
    }

    private static func code(for key: String) -> UInt32? {
        guard key.utf8.count == 4 else { return nil }
        return key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCC(_ value: UInt32) -> String {
        let scalars = [24, 16, 8, 0].map { UnicodeScalar(UInt8((value >> $0) & 0xFF)) }
        return String(String.UnicodeScalarView(scalars))
    }
}
