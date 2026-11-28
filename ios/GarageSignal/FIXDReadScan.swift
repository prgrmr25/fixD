import DiagnosticsCore
import Foundation

struct FIXDScanSnapshot {
    struct Reading: Identifiable {
        let ecu: String
        let pid: CurrentDataPID
        let title: String
        let value: Double
        let unit: String

        var id: String { ecu + ":" + String(pid.rawValue) }
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

struct FIXDMisfireSnapshot {
    let capturedAt: Date
    let ecu: String
    let countsByCylinder: [Int: UInt16]
    let status: String
}

struct HondaTransmissionCapture {
    let distinctionCode: String
    let dataStatus: String
    let rawHex: String?
}

struct HondaModuleProbeResult {
    let probe: HondaModuleProbe
    let responder: String
    let payload: [UInt8]
    let transmission: HondaTransmissionCapture?

    var did: String { String(format: "%04X", Int(probe.dataIdentifier)) }
    var byteCount: Int { payload.count }
    var rawHex: String { payload.map { String(format: "%02X", Int($0)) }.joined(separator: " ") }
}

@MainActor
enum FIXDReadScan {
    struct Connection {
        let vehicleProtocol: String
        let supportsHondaModuleProbes: Bool
        fileprivate let sessionID: ObjectIdentifier
        fileprivate let supportedPIDsByECU: [String: Set<UInt8>]

        var responders: [String] { supportedPIDsByECU.keys.sorted() }
    }

    struct CurrentDataFrame {
        let capturedAt: Date
        let readings: [FIXDScanSnapshot.Reading]
        let unavailableReadings: [String]
    }

    enum ModuleOutcome {
        case response(HondaModuleProbeResult)
        case noResponse(HondaStandardControlStatus?)
        case rejected(UInt8)
    }

    enum Failure: LocalizedError {
        case unexpectedProtocol
        case noSupportedPIDReply
        case mismatchedConnection
        case unsupportedModuleProtocol
        case missingMDXPCMResponder

        var errorDescription: String? {
            switch self {
            case .unexpectedProtocol:
                return "This beta supports confirmed ISO 15765-4 CAN sessions. The adapter reported another protocol."
            case .noSupportedPIDReply:
                return "No vehicle ECU returned a supported-PID bitmap. Check ignition and adapter connection."
            case .mismatchedConnection:
                return "Vehicle data must be read through the adapter session that discovered it."
            case .unsupportedModuleProtocol:
                return "Honda module scans require a 29-bit CAN connection at 500 kbit/s."
            case .missingMDXPCMResponder:
                return "The expected 2011 MDX PCM did not appear in the standard OBD-II replies."
            }
        }
    }

    static func run(
        using session: FIXDLiveSession,
        progress: (String) -> Void
    ) async throws -> FIXDScanSnapshot {
        let connection = try await connect(using: session, progress: progress)
        progress("Reading vehicle data supported by the responding ECUs…")
        let frame = try await readCurrentData(using: session, connection: connection, includeScanOnly: true)
        progress("Reading stored, pending and permanent trouble codes…")
        let codeGroups = try await readTroubleCodes(using: session)
        return FIXDScanSnapshot(
            capturedAt: frame.capturedAt,
            vehicleProtocol: connection.vehicleProtocol,
            responders: connection.responders,
            readings: frame.readings,
            troubleCodes: codeGroups,
            unavailableReadings: frame.unavailableReadings
        )
    }

    /// Configure the adapter once and identify the PIDs advertised by each ECU.
    static func connect(
        using session: FIXDLiveSession,
        discoverAdditionalPIDs: Bool = true,
        progress: (String) -> Void
    ) async throws -> Connection {
        if !session.isReady {
            progress("Preparing the selected FIXD adapter…")
            try await session.start()
        }

        progress("Checking for a standard OBD-II response…")
        let probe = DiagnosticRequest.currentData(.supported01Through20)
        let reply = try await session.read(probe)
        let protocolReply = try await session.readAdapterProtocol()
        let vehicleProtocol = try canProtocol(protocolReply)
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

        // Standard continuation bits qualify the next bitmap for each ECU independently.
        let additionalPages: [CurrentDataPID] = discoverAdditionalPIDs
            ? [.supported21Through40, .supported41Through60]
            : []
        for page in additionalPages {
            try Task.checkCancellation()
            let expected = Set(supportByECU.filter { $0.value.contains(page.rawValue) }.keys)
            guard !expected.isEmpty else { break }
            progress("Checking additional standard signals…")
            let request = DiagnosticRequest.currentData(page)
            let response = try await session.read(request)
            // A complete but invalid optional bitmap leaves the base signal list usable.
            guard let pageAnswers = try? ELMResponseParser.parse(response, for: request) else { break }
            for answer in pageAnswers {
                let ecu = answer.responder.hexIdentifier
                if expected.contains(ecu), case .currentData(.supportedPIDs(let supported)) = answer.outcome {
                    supportByECU[ecu, default: []].formUnion(supported)
                }
            }
        }

        return Connection(
            vehicleProtocol: vehicleProtocol.name,
            supportsHondaModuleProbes: vehicleProtocol.hondaModuleProbes,
            sessionID: ObjectIdentifier(session),
            supportedPIDsByECU: supportByECU
        )
    }

    /// Request a new set of readings without repeating adapter setup or reading DTCs.
    static func readCurrentData(
        using session: FIXDLiveSession,
        connection: Connection,
        includeScanOnly: Bool = false,
        shouldContinue: () -> Bool = { true }
    ) async throws -> CurrentDataFrame {
        guard connection.sessionID == ObjectIdentifier(session) else { throw Failure.mismatchedConnection }
        var readings: [FIXDScanSnapshot.Reading] = []
        var unavailable: [String] = []
        let requested = includeScanOnly ? measurements + scanOnlyMeasurements : measurements
        for (pid, title) in requested {
            try Task.checkCancellation()
            guard shouldContinue() else { throw CancellationError() }
            let expected = Set(connection.supportedPIDsByECU.compactMap { ecu, supported -> String? in
                supported.contains(pid.rawValue) ? ecu : nil
            })
            guard !expected.isEmpty else {
                unavailable.append(title)
                continue
            }

            let request = DiagnosticRequest.currentData(pid)
            let response = try await session.read(request)
            var observed = Set<String>()
            for answer in try optionalAnswers(response, for: request) {
                let ecu = answer.responder.hexIdentifier
                guard expected.contains(ecu),
                      case .currentData(.measurement(let value, let unit)) = answer.outcome
                else { continue }
                readings.append(.init(ecu: ecu, pid: pid, title: title, value: value, unit: unitName(unit)))
                observed.insert(ecu)
            }
            unavailable.append(contentsOf: expected.subtracting(observed).sorted().map {
                "\(title) · ECU \($0)"
            })
        }
        return CurrentDataFrame(capturedAt: .now, readings: readings, unavailableReadings: unavailable)
    }

    /// Scan the documented 2011 MDX cylinder monitors through the standard OBD-II route.
    static func readMisfires(
        using session: FIXDLiveSession,
        connection: Connection,
        trace: (String) -> Void
    ) async throws -> FIXDMisfireSnapshot {
        guard connection.sessionID == ObjectIdentifier(session) else { throw Failure.mismatchedConnection }
        guard connection.supportsHondaModuleProbes else { throw Failure.unsupportedModuleProtocol }
        let ecu = HondaModuleProbe.powertrain.responseCANID
        guard connection.responders.contains(ecu) else { throw Failure.missingMDXPCMResponder }

        var supported: Set<UInt8> = [0]
        for page in MisfireMonitorID.capabilityPages {
            guard supported.contains(page.rawValue) else {
                return .init(capturedAt: .now, ecu: ecu, countsByCylinder: [:],
                             status: "The PCM did not advertise the cylinder misfire monitor page.")
            }
            let answer = try await monitorReply(page, from: ecu, using: session, trace: trace)
            guard case .some(.monitorData(.supportedMonitors(let monitors))) = answer else {
                return .init(capturedAt: .now, ecu: ecu, countsByCylinder: [:],
                             status: "The PCM did not return a usable Mode 06 capability page.")
            }
            supported = monitors
        }

        var counts: [Int: UInt16] = [:]
        let advertised = MisfireMonitorID.cylinders.filter { supported.contains($0.rawValue) }
        for monitor in advertised {
            let answer = try await monitorReply(monitor, from: ecu, using: session, trace: trace)
            if case .some(.monitorData(.cycleMisfireCount(let count?))) = answer,
               let cylinder = monitor.cylinderNumber {
                counts[cylinder] = count
            }
        }
        let status: String
        if advertised.isEmpty {
            status = "The PCM advertised no 2011 MDX cylinder misfire monitors."
        } else if counts.isEmpty {
            status = "The PCM advertised cylinder monitors. No drive-cycle counts were returned."
        } else {
            status = "Drive-cycle counts returned for \(counts.count) of 6 cylinders."
        }
        return .init(capturedAt: .now, ecu: ecu, countsByCylinder: counts, status: status)
    }

    private static func monitorReply(
        _ monitor: MisfireMonitorID,
        from ecu: String,
        using session: FIXDLiveSession,
        trace: (String) -> Void
    ) async throws -> DiagnosticOutcome? {
        try Task.checkCancellation()
        let request = DiagnosticRequest.monitorData(monitor)
        let reply = try await session.read(request)
        trace(String(format: "06%02X", Int(monitor.rawValue)) + ":\n" + reply)
        return try optionalAnswers(reply, for: request, limitingToResponder: ecu).first?.outcome
    }

    /// Capture an on-demand DTC snapshot independently from live polling.
    static func readTroubleCodes(using session: FIXDLiveSession) async throws -> [FIXDScanSnapshot.TroubleCodes] {
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
                case .currentData, .manufacturerData, .monitorData:
                    return nil
                }
            }
            codeGroups.append(.init(title: title, ecus: ecus, status: ecus.isEmpty ? "No data returned." : nil))
        }

        return codeGroups
    }

    static func readModule(
        _ probe: HondaModuleProbe,
        using session: FIXDLiveSession,
        connection: Connection,
        trace: (String) -> Void
    ) async throws -> ModuleOutcome {
        guard connection.sessionID == ObjectIdentifier(session) else { throw Failure.mismatchedConnection }
        guard connection.supportsHondaModuleProbes else { throw Failure.unsupportedModuleProtocol }
        let reply = try await session.readModule(
            probe,
            checkDirectedOBD: connection.responders.contains(probe.responseCANID),
            trace: trace
        )
        let control = reply.directedControl.map { probe.standardControlStatus(reply: $0) }
        let answers = try optionalAnswers(reply.hondaReply, for: .hondaData(probe))
        guard let answer = answers.first else { return .noResponse(control) }
        if case .manufacturerData(let payload) = answer.outcome {
            let transmission = probe == .transmission
                ? transmissionCapture(identityReply: reply.hondaReply, dataReply: reply.transmissionDataReply)
                : nil
            return .response(.init(probe: probe, responder: answer.responder.hexIdentifier,
                                   payload: payload, transmission: transmission))
        }
        if case .negativeResponse(let code) = answer.outcome {
            return .rejected(code)
        }
        return .noResponse(control)
    }

    private static func transmissionCapture(identityReply: String, dataReply: String?) -> HondaTransmissionCapture? {
        guard let identification = HondaAutomaticTransmission.identification(reply: identityReply) else { return nil }
        let distinctionCode = String(format: "0x%02X", Int(identification.distinctionCode))

        let status: String
        var rawHex: String?
        do {
            if let dataReply, let answer = try optionalAnswers(dataReply, for: .hondaTransmissionData).first {
                switch answer.outcome {
                case .manufacturerData(let bytes):
                    if bytes.count == 36 {
                        rawHex = bytes.map { String(format: "%02X", Int($0)) }.joined(separator: " ")
                        status = "Data list returned 36 bytes. Field values need vehicle validation."
                    } else {
                        status = "The data list returned a different length from the reference layout."
                    }
                case .negativeResponse(let code):
                    status = "The ECU declined the data list read (" + String(format: "0x%02X", Int(code)) + ")."
                case .currentData, .troubleCodes, .monitorData:
                    status = "The response did not match the transmission data list."
                }
            } else {
                status = "The adapter returned no data for the transmission data list."
            }
        } catch {
            status = error.localizedDescription
        }
        return HondaTransmissionCapture(distinctionCode: distinctionCode, dataStatus: status, rawHex: rawHex)
    }

    private static func optionalAnswers(
        _ reply: String,
        for request: DiagnosticRequest,
        limitingToResponder ecu: String? = nil
    ) throws -> [DiagnosticResponse] {
        do {
            return try ELMResponseParser.parse(reply, for: request, limitingToResponder: ecu)
        } catch ELMResponseError.noData {
            return []
        }
    }

    private static func canProtocol(_ reply: String) throws -> (name: String, hondaModuleProbes: Bool) {
        let meaningfulLines = reply.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty && $0 != "ATDPN" }
        guard meaningfulLines.count == 1, let line = meaningfulLines.first else {
            throw Failure.unexpectedProtocol
        }
        let code = line.hasPrefix("A") ? String(line.dropFirst()) : line
        switch code {
        case "6": return ("ISO 15765-4 CAN · 11-bit, 500 kbit/s", false)
        case "7": return ("ISO 15765-4 CAN · 29-bit, 500 kbit/s", true)
        case "8": return ("ISO 15765-4 CAN · 11-bit, 250 kbit/s", false)
        case "9": return ("ISO 15765-4 CAN · 29-bit, 250 kbit/s", false)
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
        case .volts: return "V"
        case .kilopascals: return "kPa"
        case .gramsPerSecond: return "g/s"
        }
    }

    private static let measurements: [(CurrentDataPID, String)] = [
        (.engineSpeed, "Engine RPM"),
        (.vehicleSpeed, "Vehicle speed"),
        (.coolantTemperature, "Coolant temperature"),
        (.calculatedEngineLoad, "Calculated engine load"),
        (.throttlePosition, "Throttle position"),
        (.ignitionAdvance, "Ignition advance"),
        (.shortTermFuelTrimBank1, "Short-term fuel trim, bank 1"),
        (.longTermFuelTrimBank1, "Long-term fuel trim, bank 1"),
        (.shortTermFuelTrimBank2, "Short-term fuel trim, bank 2"),
        (.longTermFuelTrimBank2, "Long-term fuel trim, bank 2"),
        (.engineOilTemperature, "Engine oil temperature"),
        (.controlModuleVoltage, "Module voltage"),
    ]

    private static let scanOnlyMeasurements: [(CurrentDataPID, String)] = [
        (.intakeManifoldAbsolutePressure, "Intake manifold absolute pressure"),
        (.intakeAirTemperature, "Intake air temperature"),
        (.massAirFlow, "Mass airflow"),
        (.barometricPressure, "Barometric pressure")
    ]

    private static let codeCategories: [(TroubleCodeCategory, String)] = [
        (.stored, "Stored codes"), (.pending, "Pending codes"), (.permanent, "Permanent codes")
    ]
}
