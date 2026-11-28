import Combine
import DiagnosticsCore
import Foundation

enum TelemetrySource: String {
    case vehicle
    case demo
}

@MainActor
final class VehicleTelemetry: ObservableObject {
    struct Reading: Identifiable {
        let ecu: String
        let value: Double

        var id: String { ecu }
    }

    private struct Channel: Hashable {
        let pid: CurrentDataPID
        let ecu: String
    }

    @Published private(set) var isAdapterConnected = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastScanOnlyUpdated: Date?
    @Published private(set) var responders: [String] = []
    @Published private(set) var troubleCodes: [FIXDScanSnapshot.TroubleCodes] = []
    @Published private var latest: [CurrentDataPID: [Reading]] = [:]
    @Published private var scanOnlyReadings: [CurrentDataPID: [Reading]] = [:]

    private var recent: [Channel: [Double]] = [:]
    private let historyLimit = 60

    func readings(for metric: DemoMetric) -> [Reading] {
        readings(forPID: Self.pid(for: metric))
    }

    func readings(forPID pid: CurrentDataPID) -> [Reading] {
        let readings = pid.isScanOnlyMeasurement ? scanOnlyReadings : latest
        return readings[pid] ?? []
    }

    func history(for metric: DemoMetric, ecu: String) -> [Double] {
        recent[Channel(pid: Self.pid(for: metric), ecu: ecu)] ?? []
    }

    func clearForNewAdapter() {
        isAdapterConnected = false
        isMonitoring = false
        lastUpdated = nil
        lastScanOnlyUpdated = nil
        responders = []
        troubleCodes = []
        latest = [:]
        scanOnlyReadings = [:]
        recent = [:]
    }

    func setAdapterConnected(_ connected: Bool) {
        isAdapterConnected = connected
        if !connected { isMonitoring = false }
    }

    func markResponders(_ ecuIDs: [String]) {
        responders = ecuIDs
    }

    func setMonitoring(_ active: Bool) {
        isMonitoring = active
    }

    func record(readings: [FIXDScanSnapshot.Reading], capturedAt: Date) {
        var channels: [CurrentDataPID: [Reading]] = [:]
        for reading in readings where !reading.pid.isScanOnlyMeasurement {
            guard reading.value.isFinite else { continue }
            let value = Self.displayValue(reading.value, for: reading.pid)
            let channel = Channel(pid: reading.pid, ecu: reading.ecu)
            channels[reading.pid, default: []].append(Reading(ecu: reading.ecu, value: value))
            recent[channel, default: []].append(value)
            if let count = recent[channel]?.count, count > historyLimit {
                recent[channel]?.removeFirst(count - historyLimit)
            }
        }
        latest = channels.mapValues { $0.sorted { $0.ecu < $1.ecu } }
        if !channels.isEmpty { lastUpdated = capturedAt }
    }

    func recordScanOnly(readings: [FIXDScanSnapshot.Reading], capturedAt: Date) {
        var channels: [CurrentDataPID: [Reading]] = [:]
        for reading in readings where reading.pid.isScanOnlyMeasurement && reading.value.isFinite {
            let value = Self.displayValue(reading.value, for: reading.pid)
            channels[reading.pid, default: []].append(Reading(ecu: reading.ecu, value: value))
        }
        scanOnlyReadings = channels.mapValues { $0.sorted { $0.ecu < $1.ecu } }
        lastScanOnlyUpdated = channels.isEmpty ? nil : capturedAt
    }

    func recordTroubleCodes(_ groups: [FIXDScanSnapshot.TroubleCodes]) {
        troubleCodes = groups
    }

    private static func pid(for metric: DemoMetric) -> CurrentDataPID {
        switch metric {
        case .engineSpeed: return .engineSpeed
        case .vehicleSpeed: return .vehicleSpeed
        case .coolant: return .coolantTemperature
        case .ignition: return .ignitionAdvance
        case .load: return .calculatedEngineLoad
        case .throttle: return .throttlePosition
        case .voltage: return .controlModuleVoltage
        case .shortTrimBank1: return .shortTermFuelTrimBank1
        case .longTrimBank1: return .longTermFuelTrimBank1
        case .shortTrimBank2: return .shortTermFuelTrimBank2
        case .longTrimBank2: return .longTermFuelTrimBank2
        }
    }

    private static func displayValue(_ value: Double, for pid: CurrentDataPID) -> Double {
        switch pid {
        case .vehicleSpeed: return value / 1.609344
        case .coolantTemperature, .intakeAirTemperature, .engineOilTemperature: return value * 9 / 5 + 32
        default: return value
        }
    }
}
