import Foundation

public enum TroubleCodeCategory: UInt8, CaseIterable, Sendable {
    case stored = 0x03
    case pending = 0x07
    case permanent = 0x0A
}

/// Fixed diagnostic reads that the transport is allowed to request.
public enum DiagnosticRequest: Equatable, Sendable {
    case currentData(CurrentDataPID)
    case monitorData(MisfireMonitorID)
    case troubleCodes(TroubleCodeCategory)
    case hondaData(HondaModuleProbe)
    case hondaTransmissionData

    public var requestPayload: [UInt8] {
        switch self {
        case let .currentData(pid): return pid.requestPayload
        case let .monitorData(monitor): return monitor.requestPayload
        case let .troubleCodes(category): return [category.rawValue]
        case let .hondaData(probe):
            let identifier = probe.dataIdentifier
            return [0x22, UInt8(identifier >> 8), UInt8(truncatingIfNeeded: identifier)]
        case .hondaTransmissionData:
            return [0x22, 0x22, 0x01]
        }
    }

    fileprivate var service: UInt8 { requestPayload[0] }

    fileprivate var hondaResponseCANID: String? {
        switch self {
        case let .hondaData(probe): return probe.responseCANID
        case .hondaTransmissionData: return HondaModuleProbe.transmission.responseCANID
        case .currentData, .monitorData, .troubleCodes: return nil
        }
    }
}

public struct CANResponder: Hashable, Sendable {
    public enum Width: Hashable, Sendable {
        case standard11Bit
        case extended29Bit
    }

    public let identifier: UInt32
    public let width: Width

    public var hexIdentifier: String {
        let text = String(identifier, radix: 16, uppercase: true)
        let digits = width == .standard11Bit ? 3 : 8
        return String(repeating: "0", count: max(0, digits - text.count)) + text
    }
}

public enum DiagnosticOutcome: Equatable, Sendable {
    case currentData(CurrentDataValue)
    case monitorData(MisfireMonitorValue)
    case troubleCodes([String])
    /// Opaque data record. The matching service and identifier have been removed.
    case manufacturerData([UInt8])
    case negativeResponse(code: UInt8)
}

public struct DiagnosticResponse: Equatable, Sendable {
    public let responder: CANResponder
    public let payload: [UInt8]
    public let outcome: DiagnosticOutcome
}

public enum ELMResponseError: LocalizedError, Equatable {
    case noData
    case emptyResponse
    case malformedReply
    case adapterStatus(String)
    case invalidFrame(line: Int)
    case invalidTransport(responder: CANResponder, line: Int)
    case incompleteTransport(responder: CANResponder)
    case unexpectedResponder(expected: String, received: CANResponder)
    case unexpectedResponse(responder: CANResponder)
    case currentData(responder: CANResponder, reason: CurrentDataDecodingError)
    case monitorData(responder: CANResponder, reason: MisfireMonitorDecodingError)
    case invalidTroubleCodes(responder: CANResponder)
    case invalidManufacturerData(responder: CANResponder)
    case conflictingResponses(responder: CANResponder)

    public var errorDescription: String? {
        switch self {
        case .noData:
            return "The adapter reported no data."
        case .emptyResponse:
            return "The adapter returned an empty diagnostic reply."
        case .malformedReply:
            return "The adapter reply was malformed."
        case let .adapterStatus(status):
            return "The adapter reported \(status)."
        case let .invalidFrame(line):
            return "Line \(line) is missing a recognized diagnostic CAN header or valid CAN data."
        case let .invalidTransport(responder, line):
            return "ECU \(responder.hexIdentifier) returned an invalid ISO-TP frame on line \(line)."
        case let .incompleteTransport(responder):
            return "The ISO-TP response from ECU \(responder.hexIdentifier) ended early."
        case let .unexpectedResponder(expected, received):
            return "Expected a reply from ECU \(expected), but ECU \(received.hexIdentifier) responded."
        case let .unexpectedResponse(responder):
            return "ECU \(responder.hexIdentifier) returned a response for a different request."
        case let .currentData(responder, _):
            return "ECU \(responder.hexIdentifier) returned invalid current data for the requested PID."
        case let .monitorData(responder, _):
            return "ECU \(responder.hexIdentifier) returned invalid data for the requested monitor."
        case let .invalidTroubleCodes(responder):
            return "ECU \(responder.hexIdentifier) returned an invalid trouble-code list."
        case let .invalidManufacturerData(responder):
            return "ECU \(responder.hexIdentifier) returned an incomplete manufacturer data record."
        case let .conflictingResponses(responder):
            return "ECU \(responder.hexIdentifier) returned conflicting responses."
        }
    }
}

/// Parses one completed ELM-style reply from an ISO 15765-4 CAN session with
/// headers and ISO-TP PCI bytes visible. Spaces and a final prompt are optional.
public enum ELMResponseParser {
    private static let adapterStatuses: Set<String> = [
        "?", "OK", "STOPPED", "UNABLE TO CONNECT", "BUS BUSY", "BUS ERROR",
        "BUS INIT: ERROR", "CAN ERROR", "BUFFER FULL", "DATA ERROR", "<DATA ERROR",
        "FB ERROR", "RX ERROR", "<RX ERROR", "LV RESET", "ACT ALERT", "LP ALERT"
    ]

    public static func parse(
        _ reply: String,
        for request: DiagnosticRequest,
        limitingToResponder responderCANID: String? = nil
    ) throws -> [DiagnosticResponse] {
        guard reply.utf8.count <= 16_385, reply.utf8.allSatisfy({
            (0x20...0x7E).contains($0) || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D
        }) else { throw ELMResponseError.malformedReply }

        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.last == ">" ? trimmed.dropLast() : trimmed[...]
        guard !body.contains(">") else { throw ELMResponseError.malformedReply }

        let echo = String(decoding: ASCIIPromptFramer.encode(request).dropLast(), as: UTF8.self)
        let expectedHondaResponder = request.hondaResponseCANID
        var order: [CANResponder] = []
        var seen: Set<CANResponder> = []
        var responses: [CANResponder: DiagnosticResponse] = [:]
        var transfers: [CANResponder: Transfer] = [:]
        var noData = false

        for (index, rawLine) in body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            var line = rawLine.trimmingCharacters(in: .whitespaces).uppercased()
            if line.hasPrefix("SEARCHING...") {
                line = line.dropFirst("SEARCHING...".count).trimmingCharacters(in: .whitespaces)
            }
            let compact = line.filter { !$0.isWhitespace }
            if compact.isEmpty || compact == echo { continue }
            if compact == "NODATA" {
                noData = true
                continue
            }
            if adapterStatuses.contains(line) || line.hasPrefix("ERR") || line.hasPrefix("BUS INIT:") {
                throw ELMResponseError.adapterStatus(line)
            }

            let lineNumber = index + 1
            let frame = try CANFrame(compact, line: lineNumber)
            if let expectedHondaResponder,
               frame.responder.width != .extended29Bit || frame.responder.hexIdentifier != expectedHondaResponder {
                throw ELMResponseError.unexpectedResponder(expected: expectedHondaResponder, received: frame.responder)
            }
            if let responderCANID, frame.responder.hexIdentifier != responderCANID { continue }
            if seen.insert(frame.responder).inserted {
                order.append(frame.responder)
            }
            guard let payload = try complete(frame, line: lineNumber, transfers: &transfers) else { continue }
            let response = try decode(payload, from: frame.responder, for: request)
            if let previous = responses[frame.responder], previous != response,
               previous.outcome != .negativeResponse(code: 0x78) {
                throw ELMResponseError.conflictingResponses(responder: frame.responder)
            }
            responses[frame.responder] = response
        }

        guard !noData else {
            if order.isEmpty { throw ELMResponseError.noData }
            throw ELMResponseError.adapterStatus("NO DATA alongside CAN frames")
        }
        guard !order.isEmpty else {
            if responderCANID != nil { return [] }
            throw ELMResponseError.emptyResponse
        }
        return try order.map { responder in
            guard transfers[responder] == nil, let response = responses[responder] else {
                throw ELMResponseError.incompleteTransport(responder: responder)
            }
            return response
        }
    }

    private struct CANFrame {
        let responder: CANResponder
        let data: [UInt8]

        init(_ compact: String, line: Int) throws {
            let malformed = ELMResponseError.invalidFrame(line: line)
            guard compact.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x41...0x46).contains($0) }) else {
                throw malformed
            }
            let header: Substring
            let width: CANResponder.Width
            if compact.hasPrefix("18DAF1") {
                header = compact.prefix(8)
                width = .extended29Bit
            } else {
                header = compact.prefix(3)
                guard let identifier = UInt32(header, radix: 16), (0x7E8...0x7EF).contains(identifier) else {
                    throw malformed
                }
                width = .standard11Bit
            }
            guard header.count == (width == .standard11Bit ? 3 : 8),
                  let identifier = UInt32(header, radix: 16)
            else { throw malformed }

            var hex = compact.dropFirst(header.count)
            var displayedLength: Int?
            if hex.count % 2 == 1 {
                displayedLength = Int(hex.prefix(1), radix: 16)
                guard displayedLength != nil else { throw malformed }
                hex = hex.dropFirst()
            }
            let byteCount = hex.count / 2
            guard (1...8).contains(byteCount), displayedLength == nil || displayedLength == byteCount else {
                throw malformed
            }

            var bytes: [UInt8] = []
            while !hex.isEmpty {
                guard let byte = UInt8(hex.prefix(2), radix: 16) else { throw malformed }
                bytes.append(byte)
                hex = hex.dropFirst(2)
            }
            responder = CANResponder(identifier: identifier, width: width)
            data = bytes
        }
    }

    private struct Transfer {
        let length: Int
        var payload: [UInt8]
        var nextSequence: UInt8 = 1
    }

    private static func complete(
        _ frame: CANFrame,
        line: Int,
        transfers: inout [CANResponder: Transfer]
    ) throws -> [UInt8]? {
        let bytes = frame.data
        let lowNibble = bytes[0] & 0x0F
        let invalid = ELMResponseError.invalidTransport(responder: frame.responder, line: line)
        switch bytes[0] >> 4 {
        case 0:
            let length = Int(lowNibble)
            guard transfers[frame.responder] == nil, (1...7).contains(length), bytes.count - 1 >= length else {
                throw invalid
            }
            return Array(bytes.dropFirst().prefix(length))
        case 1:
            guard transfers[frame.responder] == nil, bytes.count == 8 else { throw invalid }
            let length = Int(lowNibble) * 256 + Int(bytes[1])
            guard length > 7 else { throw invalid }
            transfers[frame.responder] = Transfer(length: length, payload: Array(bytes.dropFirst(2)))
            return nil
        case 2:
            guard var transfer = transfers[frame.responder], lowNibble == transfer.nextSequence else {
                throw invalid
            }
            let remaining = transfer.length - transfer.payload.count
            let available = bytes.count - 1
            guard available > 0, available >= remaining || bytes.count == 8 else { throw invalid }
            transfer.payload.append(contentsOf: bytes.dropFirst().prefix(remaining))
            if transfer.payload.count == transfer.length {
                transfers.removeValue(forKey: frame.responder)
                return transfer.payload
            }
            transfer.nextSequence = (transfer.nextSequence + 1) & 0x0F
            transfers[frame.responder] = transfer
            return nil
        default:
            throw invalid
        }
    }

    private static func decode(
        _ payload: [UInt8],
        from responder: CANResponder,
        for request: DiagnosticRequest
    ) throws -> DiagnosticResponse {
        let outcome: DiagnosticOutcome
        if payload[0] == 0x7F {
            guard payload.count == 3, payload[1] == request.service else {
                throw ELMResponseError.unexpectedResponse(responder: responder)
            }
            outcome = .negativeResponse(code: payload[2])
        } else {
            guard payload[0] == request.service + 0x40 else {
                throw ELMResponseError.unexpectedResponse(responder: responder)
            }
            switch request {
            case let .currentData(pid):
                do {
                    outcome = .currentData(try CurrentDataDecoder.decode(payload, for: pid))
                } catch let error as CurrentDataDecodingError {
                    throw ELMResponseError.currentData(responder: responder, reason: error)
                }
            case let .monitorData(monitor):
                do {
                    outcome = .monitorData(try MisfireMonitorDecoder.decode(payload, for: monitor))
                } catch let error as MisfireMonitorDecodingError {
                    throw ELMResponseError.monitorData(responder: responder, reason: error)
                }
            case .troubleCodes:
                guard payload.count >= 2, payload.count == 2 + Int(payload[1]) * 2 else {
                    throw ELMResponseError.invalidTroubleCodes(responder: responder)
                }
                var codes: [String] = []
                for index in stride(from: 2, to: payload.count, by: 2) {
                    let value = UInt16(payload[index]) << 8 | UInt16(payload[index + 1])
                    guard value != 0 else { throw ELMResponseError.invalidTroubleCodes(responder: responder) }
                    codes.append(troubleCode(value))
                }
                outcome = .troubleCodes(codes)
            case .hondaData, .hondaTransmissionData:
                guard payload.count > 3 else {
                    throw ELMResponseError.invalidManufacturerData(responder: responder)
                }
                guard payload[1...2].elementsEqual(request.requestPayload.dropFirst()) else {
                    throw ELMResponseError.unexpectedResponse(responder: responder)
                }
                outcome = .manufacturerData(Array(payload.dropFirst(3)))
            }
        }
        return DiagnosticResponse(responder: responder, payload: payload, outcome: outcome)
    }

    private static func troubleCode(_ value: UInt16) -> String {
        let group = ["P", "C", "B", "U"][Int(value >> 14)]
        let digits = String(value & 0x3FFF, radix: 16, uppercase: true)
        return group + String(repeating: "0", count: 4 - digits.count) + digits
    }
}
