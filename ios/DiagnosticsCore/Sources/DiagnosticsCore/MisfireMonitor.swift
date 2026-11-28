/// The SAE J1979 service 06 bitmap pages and cylinder monitors used by the 2011 Acura MDX.
public enum MisfireMonitorID: UInt8, Sendable {
    case supported01Through20 = 0x00
    case supported21Through40 = 0x20
    case supported41Through60 = 0x40
    case supported61Through80 = 0x60
    case supported81ThroughA0 = 0x80
    case supportedA1ThroughC0 = 0xA0
    case cylinder1 = 0xA2
    case cylinder2 = 0xA3
    case cylinder3 = 0xA4
    case cylinder4 = 0xA5
    case cylinder5 = 0xA6
    case cylinder6 = 0xA7

    public static let capabilityPages: [Self] = [
        .supported01Through20, .supported21Through40, .supported41Through60,
        .supported61Through80, .supported81ThroughA0, .supportedA1ThroughC0,
    ]
    public static let cylinders: [Self] = [.cylinder1, .cylinder2, .cylinder3, .cylinder4, .cylinder5, .cylinder6]

    public var cylinderNumber: Int? {
        guard let index = Self.cylinders.firstIndex(of: self) else { return nil }
        return index + 1
    }

    public var requestPayload: [UInt8] { [0x06, rawValue] }
}

public enum MisfireMonitorValue: Equatable, Sendable {
    /// Absolute monitor IDs, including the next bitmap page when advertised.
    case supportedMonitors(Set<UInt8>)
    /// The ECU's last or current cycle result. Nil means no completed TID 0C result.
    case cycleMisfireCount(UInt16?)
}

public enum MisfireMonitorDecodingError: Error, Equatable {
    case invalidCapabilityLength
    case invalidRecordLength
    case mismatchedMonitor(expected: UInt8, received: UInt8)
    case unexpectedScaling(UInt8)
    case duplicateCycleTest
}

enum MisfireMonitorDecoder {
    static func decode(_ payload: [UInt8], for monitor: MisfireMonitorID) throws -> MisfireMonitorValue {
        if MisfireMonitorID.capabilityPages.contains(monitor) {
            guard payload.count == 6 else { throw MisfireMonitorDecodingError.invalidCapabilityLength }
            try checkMonitor(payload[1], expected: monitor)
            return .supportedMonitors(SAECapabilityBitmap.decode(payload[2...], base: monitor.rawValue))
        }

        // Each test record repeats its MID, followed by TID, scaling, result and two limits.
        let recordLength = 9
        guard payload.count > 1, (payload.count - 1).isMultiple(of: recordLength) else {
            throw MisfireMonitorDecodingError.invalidRecordLength
        }

        var foundCycleTest = false
        var cycleCount: UInt16?
        for start in stride(from: 1, to: payload.count, by: recordLength) {
            try checkMonitor(payload[start], expected: monitor)
            let testID = payload[start + 1]
            guard testID == 0x0B || testID == 0x0C else { continue }
            let scaling = payload[start + 2]
            guard scaling == 0x24 else { throw MisfireMonitorDecodingError.unexpectedScaling(scaling) }
            guard testID == 0x0C else { continue }
            guard !foundCycleTest else { throw MisfireMonitorDecodingError.duplicateCycleTest }
            foundCycleTest = true

            let valueAndLimits = payload[(start + 3)..<(start + recordLength)]
            // SAE J1979 uses zero for the result and both limits before a test completes.
            if valueAndLimits.contains(where: { $0 != 0 }) {
                cycleCount = UInt16(payload[start + 3]) << 8 | UInt16(payload[start + 4])
            }
        }
        return .cycleMisfireCount(cycleCount)
    }

    private static func checkMonitor(_ received: UInt8, expected monitor: MisfireMonitorID) throws {
        guard received == monitor.rawValue else {
            throw MisfireMonitorDecodingError.mismatchedMonitor(expected: monitor.rawValue, received: received)
        }
    }
}
