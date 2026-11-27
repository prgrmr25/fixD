import DiagnosticsCore
import Foundation

struct FIXDScanSnapshot {
    struct Reading: Identifiable {
        let ecu: String
        let title: String
        let value: Double
        let unit: String

        var id: String { ecu + ":" + title }
    }

    struct TroubleCodes: Identifiable {
        struct ECU: Identifiable {
            let id: String
            let codes: [String]
            let unavailableReason: String?
        }

        let title: String
        let ecus: [ECU]
        let status: String?

        var id: String { title }
    }

    let capturedAt: Date
    let vehicleProtocol: String
    let responders: [String]
    let readings: [Reading]
    let troubleCodes: [TroubleCodes]
    let unavailableReadings: [String]
}

@MainActor
enum FIXDReadScan {
    enum Failure: LocalizedError {
        case unexpectedProtocol
        case noSupportedPIDReply

        var errorDescription: String? {
            switch self {
            case .unexpectedProtocol:
                return "This beta supports confirmed ISO 15765-4 CAN sessions. The adapter reported another protocol."
            case .noSupportedPIDReply:
                return "No vehicle ECU returned a supported-PID bitmap. Check ignition and adapter connection."
            }
        }
    }

    static func run(
        using session: FIXDLiveSession,
        progress: (String) -> Void
    ) async throws -> FIXDScanSnapshot {
        progress("Preparing the selected FIXD adapter…")
        try await session.start()

        progress("Checking for a standard OBD-II response…")
        let probe = DiagnosticRequest.currentData(.supported01Through20)
        let reply = try await session.read(probe)
        let protocolReply = try await session.readAdapterProtocol()
        let protocolName = try canProtocol(protocolReply)
        let answers: [DiagnosticResponse]
        do {
            answers = try ELMResponseParser.parse(reply, for: probe)
        } catch ELMResponseError.noData {
            throw Failure.noSupportedPIDReply
        }
        var supportByECU: [String: Set<UInt8>] = [:]
        for answer in answers {
            if case .currentData(.supportedPIDs(let set)) = answer.outcome {
                supportByECU[answer.responder.hexIdentifier, default: []].formUnion(set)
            }
        }
        guard !supportByECU.isEmpty else { throw Failure.noSupportedPIDReply }

        progress("Reading vehicle data supported by the responding ECUs…")
        var readings: [FIXDScanSnapshot.Reading] = []
        var unavailable: [String] = []
        for (pid, title) in measurements {
            try Task.checkCancellation()
            let expected = supportByECU.filter { $0.value.contains(pid.rawValue) }
            guard !expected.isEmpty else {
                unavailable.append(title)
                continue
            }

            let request = DiagnosticRequest.currentData(pid)
            let response = try await session.read(request)
            var observed = Set<String>()
            for answer in try optionalAnswers(response, for: request) {
                let ecu = answer.responder.hexIdentifier
                guard expected[ecu] != nil,
                      case .currentData(.measurement(let value, let unit)) = answer.outcome else { continue }
                readings.append(.init(ecu: ecu, title: title, value: value, unit: unitName(unit)))
                observed.insert(ecu)
            }
            unavailable.append(contentsOf: expected.keys.filter { !observed.contains($0) }.sorted().map {
                "\(title) · ECU \($0)"
            })
        }

        progress("Reading stored, pending and permanent trouble codes…")
        var codeGroups: [FIXDScanSnapshot.TroubleCodes] = []
        for (category, title) in codeCategories {
            try Task.checkCancellation()
            let request = DiagnosticRequest.troubleCodes(category)
            let response = try await session.read(request)
            let codeAnswers = try optionalAnswers(response, for: request)
            let ecus = codeAnswers.compactMap { answer -> FIXDScanSnapshot.TroubleCodes.ECU? in
                let ecu = answer.responder.hexIdentifier
                switch answer.outcome {
                case .troubleCodes(let codes):
                    return .init(id: ecu, codes: codes, unavailableReason: nil)
                case .negativeResponse(let code):
                    return .init(id: ecu, codes: [], unavailableReason: String(format: "ECU returned 0x%02X", Int(code)))
                case .currentData:
                    return nil
                }
            }
            codeGroups.append(.init(title: title, ecus: ecus, status: ecus.isEmpty ? "No data returned." : nil))
        }

        return FIXDScanSnapshot(
            capturedAt: .now,
            vehicleProtocol: protocolName,
            responders: supportByECU.keys.sorted(),
            readings: readings,
            troubleCodes: codeGroups,
            unavailableReadings: unavailable
        )
    }

    private static func optionalAnswers(
        _ reply: String,
        for request: DiagnosticRequest
    ) throws -> [DiagnosticResponse] {
        do {
            return try ELMResponseParser.parse(reply, for: request)
        } catch ELMResponseError.noData {
            return []
        }
    }

    private static func canProtocol(_ reply: String) throws -> String {
        let meaningfulLines = reply.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && $0 != "ATDPN" }
        guard meaningfulLines.count == 1, let line = meaningfulLines.first else {
            throw Failure.unexpectedProtocol
        }
        let code = line.hasPrefix("A") ? String(line.dropFirst()) : line
        switch code {
        case "6": return "ISO 15765-4 CAN · 11-bit, 500 kbit/s"
        case "7": return "ISO 15765-4 CAN · 29-bit, 500 kbit/s"
        case "8": return "ISO 15765-4 CAN · 11-bit, 250 kbit/s"
        case "9": return "ISO 15765-4 CAN · 29-bit, 250 kbit/s"
        default: throw Failure.unexpectedProtocol
        }
    }

    private static func unitName(_ unit: DiagnosticUnit) -> String {
        switch unit {
        case .celsius: return "°C"
        case .percent: return "%"
        case .rpm: return "rpm"
        case .kilometersPerHour: return "km/h"
        case .degreesBeforeTopDeadCenter: return "° BTDC"
        }
    }

    private static let measurements: [(CurrentDataPID, String)] = [
        (.engineSpeed, "Engine RPM"),
        (.vehicleSpeed, "Vehicle speed"),
        (.coolantTemperature, "Coolant temperature"),
        (.ignitionAdvance, "Ignition advance"),
        (.shortTermFuelTrimBank1, "Short-term fuel trim, bank 1"),
        (.longTermFuelTrimBank1, "Long-term fuel trim, bank 1"),
        (.shortTermFuelTrimBank2, "Short-term fuel trim, bank 2"),
        (.longTermFuelTrimBank2, "Long-term fuel trim, bank 2"),
    ]

    private static let codeCategories: [(TroubleCodeCategory, String)] = [
        (.stored, "Stored codes"), (.pending, "Pending codes"), (.permanent, "Permanent codes")
    ]
}
