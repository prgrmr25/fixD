public enum AdapterFramingError: Error, Equatable {
    case invalidASCII(UInt8)
    case responseTooLong
}

/// Reassembles ASCII adapter replies independently of BLE notification boundaries.
/// Use this framing only with an adapter profile for which it has been verified.
public struct ASCIIPromptFramer: Sendable {
    private static let maximumResponseBytes = 16_384
    private var pending: [UInt8] = []

    public init() {}

    public static func encode(_ pid: CurrentDataPID) -> [UInt8] {
        encode(.currentData(pid))
    }

    public static func encode(_ request: DiagnosticRequest) -> [UInt8] {
        let command = request.requestPayload.map { byte in
            let hex = String(byte, radix: 16, uppercase: true)
            return byte < 16 ? "0" + hex : hex
        }.joined()
        return Array((command + "\r").utf8)
    }

    /// A completed reply is returned as raw ASCII preceding the prompt so an
    /// adapter-specific decoder can distinguish echoes, text status, and frames.
    public mutating func consume(_ notification: [UInt8]) throws -> [String] {
        var completed: [String] = []
        for byte in notification {
            if byte == 0x3E {
                completed.append(String(decoding: pending, as: UTF8.self))
                reset()
                continue
            }
            guard (0x20...0x7E).contains(byte) || byte == 0x09 || byte == 0x0A || byte == 0x0D else {
                reset()
                throw AdapterFramingError.invalidASCII(byte)
            }
            guard pending.count < Self.maximumResponseBytes else {
                reset()
                throw AdapterFramingError.responseTooLong
            }
            pending.append(byte)
        }
        return completed
    }

    /// Discard a stale partial response when reconnecting or after a timeout.
    public mutating func reset() {
        pending.removeAll(keepingCapacity: true)
    }
}
