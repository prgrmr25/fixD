import Foundation

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
}
