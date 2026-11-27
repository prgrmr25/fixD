/// A read-only SAE J1979 service 01 request. These bytes describe the diagnostic
/// payload. Adapter and vehicle framing are the responsibility of the transport.
public enum CurrentDataPID: UInt8, CaseIterable, Sendable {
    case supported01Through20 = 0x00
    case calculatedEngineLoad = 0x04
    case coolantTemperature = 0x05
    case shortTermFuelTrimBank1 = 0x06
    case longTermFuelTrimBank1 = 0x07
    case shortTermFuelTrimBank2 = 0x08
    case longTermFuelTrimBank2 = 0x09
    case engineSpeed = 0x0C
    case vehicleSpeed = 0x0D
    case ignitionAdvance = 0x0E
    case throttlePosition = 0x11
    case supported21Through40 = 0x20
    case supported41Through60 = 0x40
    case controlModuleVoltage = 0x42
    case engineOilTemperature = 0x5C

    public var requestPayload: [UInt8] { [0x01, rawValue] }

    public var isCapabilityBitmap: Bool {
        switch self {
        case .supported01Through20, .supported21Through40, .supported41Through60: return true
        default: return false
        }
    }

    fileprivate var valueByteCount: Int {
        if isCapabilityBitmap { return 4 }
        switch self {
        case .engineSpeed, .controlModuleVoltage: return 2
        default: return 1
        }
    }
}

public enum DiagnosticUnit: String, Sendable {
    case celsius, percent, rpm, kilometersPerHour, degreesBeforeTopDeadCenter, volts
}

public enum CurrentDataValue: Equatable, Sendable {
    /// Absolute PID identifiers. The last bit indicates the next bitmap page.
    case supportedPIDs(Set<UInt8>)
    case measurement(Double, DiagnosticUnit)
}

public enum CurrentDataDecodingError: Error, Equatable {
    case malformedPayload
    case unexpectedService(UInt8)
    case mismatchedPID(expected: UInt8, received: UInt8)
    case negativeResponse(code: UInt8)
    case invalidLength(expected: Int, received: Int)
}

public enum CurrentDataDecoder {
    /// Decodes one complete ECU response with link-layer headers and padding removed.
    /// The transport must select the ECU and associate the response with the request.
    public static func decode(_ payload: [UInt8], for pid: CurrentDataPID) throws -> CurrentDataValue {
        guard payload.count >= 2 else { throw CurrentDataDecodingError.malformedPayload }
        switch payload[0] {
        case 0x7F:
            guard payload.count == 3 else { throw CurrentDataDecodingError.malformedPayload }
            guard payload[1] == 0x01 else { throw CurrentDataDecodingError.unexpectedService(payload[1]) }
            throw CurrentDataDecodingError.negativeResponse(code: payload[2])
        case 0x41:
            break
        default:
            throw CurrentDataDecodingError.unexpectedService(payload[0])
        }

        guard payload[1] == pid.rawValue else {
            throw CurrentDataDecodingError.mismatchedPID(expected: pid.rawValue, received: payload[1])
        }
        let count = payload.count - 2
        guard count == pid.valueByteCount else {
            throw CurrentDataDecodingError.invalidLength(expected: pid.valueByteCount, received: count)
        }
        let a = Double(payload[2])
        switch pid {
        case .supported01Through20, .supported21Through40, .supported41Through60:
            var supported = Set<UInt8>()
            for position in 0..<32 {
                let mask = UInt8(0x80) >> (position % 8)
                if payload[2 + position / 8] & mask != 0 {
                    supported.insert(pid.rawValue + UInt8(position + 1))
                }
            }
            return .supportedPIDs(supported)
        case .calculatedEngineLoad, .throttlePosition:
            return .measurement(a * 100 / 255, .percent)
        case .coolantTemperature, .engineOilTemperature:
            return .measurement(a - 40, .celsius)
        case .shortTermFuelTrimBank1, .longTermFuelTrimBank1, .shortTermFuelTrimBank2, .longTermFuelTrimBank2:
            return .measurement((a - 128) * 100 / 128, .percent)
        case .engineSpeed:
            return .measurement((a * 256 + Double(payload[3])) / 4, .rpm)
        case .vehicleSpeed:
            return .measurement(a, .kilometersPerHour)
        case .ignitionAdvance:
            return .measurement(a / 2 - 64, .degreesBeforeTopDeadCenter)
        case .controlModuleVoltage:
            return .measurement((a * 256 + Double(payload[3])) / 1000, .volts)
        }
    }
}
