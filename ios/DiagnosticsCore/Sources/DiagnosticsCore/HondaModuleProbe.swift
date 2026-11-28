import Foundation

public enum HondaStandardControlStatus: Equatable, Sendable {
    case matched
    case otherResponder
    case noData
    case invalid
}

/// Read-only Honda/Acura CAN module candidates from HDS reference data.
/// Model and calibration support must be established on the vehicle.
public enum HondaModuleProbe: String, CaseIterable, Sendable, Hashable {
    case powertrain
    case transmission
    case shawd
    case absVSA
    case tpms
    case srs
    case instrumentCluster

    public var title: String {
        switch self {
        case .powertrain: return "Engine / PCM"
        case .transmission: return "Automatic transmission"
        case .shawd: return "SH-AWD"
        case .absVSA: return "ABS / VSA"
        case .tpms: return "TPMS"
        case .srs: return "SRS"
        case .instrumentCluster: return "Instrument cluster"
        }
    }

    public var ecuAddress: UInt8 {
        switch self {
        case .powertrain: return 0x11
        case .transmission: return 0x1D
        case .shawd: return 0x25
        case .absVSA: return 0x28
        case .tpms: return 0x26
        case .srs: return 0x53
        case .instrumentCluster: return 0x60
        }
    }

    public var dataIdentifier: UInt16 {
        switch self {
        case .powertrain: return 0x2661
        case .transmission: return 0x2200
        case .shawd: return 0x6119
        case .absVSA: return 0x4000
        case .tpms: return 0x6000
        case .srs: return 0x8000
        case .instrumentCluster: return 0x7000
        }
    }

    public var requestCANID: String { String(format: "18DA%02XF1", Int(ecuAddress)) }
    public var responseCANID: String { String(format: "18DAF1%02X", Int(ecuAddress)) }

    /// Classifies a completed SAE 0100 control, which must positively identify the directed target.
    public func standardControlStatus(reply: String) -> HondaStandardControlStatus {
        do {
            let responders = try Self.positiveStandardControlResponders(reply: reply)
            guard !responders.isEmpty else { return .invalid }
            if responders.contains(where: { $0.width != .extended29Bit || $0.hexIdentifier != responseCANID }) {
                return .otherResponder
            }
            return .matched
        } catch ELMResponseError.noData {
            return .noData
        } catch {
            return .invalid
        }
    }

    /// Reports the valid extended CAN responders in one completed functional SAE 0100 reply.
    public static func functionalControlResponders(reply: String) -> [String] {
        guard let responders = try? positiveStandardControlResponders(reply: reply) else { return [] }
        return responders.filter { $0.width == .extended29Bit }.map(\.hexIdentifier).sorted()
    }

    private static func positiveStandardControlResponders(reply: String) throws -> [CANResponder] {
        try ELMResponseParser.parse(reply, for: .currentData(.supported01Through20)).compactMap { response in
            guard case .currentData(.supportedPIDs(_)) = response.outcome else { return nil }
            return response.responder
        }
    }
}
