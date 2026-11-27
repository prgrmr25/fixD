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
        let metric: DemoMetric
        let ecu: String
    }

    @Published private(set) var isAdapterConnected = false
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var responders: [String] = []
    @Published private(set) var troubleCodes: [FIXDScanSnapshot.TroubleCodes] = []
    @Published private var latest: [DemoMetric: [Reading]] = [:]

    private var recent: [Channel: [Double]] = [:]
    private let historyLimit = 60

    func readings(for metric: DemoMetric) -> [Reading] {
        latest[metric] ?? []
    }

    func history(for metric: DemoMetric, ecu: String) -> [Double] {
        recent[Channel(metric: metric, ecu: ecu)] ?? []
    }

    func clearForNewAdapter() {
        isAdapterConnected = false
        isMonitoring = false
        lastUpdated = nil
        responders = []
        troubleCodes = []
        latest = [:]
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
        var channels: [DemoMetric: [Reading]] = [:]
        for reading in readings {
            guard let metric = Self.metric(for: reading.pid), reading.value.isFinite else { continue }
            let value = Self.displayValue(reading.value, for: metric)
            let channel = Channel(metric: metric, ecu: reading.ecu)
            channels[metric, default: []].append(Reading(ecu: reading.ecu, value: value))
            recent[channel, default: []].append(value)
            if let count = recent[channel]?.count, count > historyLimit {
                recent[channel]?.removeFirst(count - historyLimit)
            }
        }
        latest = channels.mapValues { $0.sorted { $0.ecu < $1.ecu } }
        if !channels.isEmpty { lastUpdated = capturedAt }
    }

    func recordTroubleCodes(_ groups: [FIXDScanSnapshot.TroubleCodes]) {
        troubleCodes = groups
    }

    private static func metric(for pid: CurrentDataPID) -> DemoMetric? {
        switch pid {
        case .engineSpeed: return .engineSpeed
        case .vehicleSpeed: return .vehicleSpeed
        case .coolantTemperature: return .coolant
        case .ignitionAdvance: return .ignition
        case .calculatedEngineLoad: return .load
        case .throttlePosition: return .throttle
        case .shortTermFuelTrimBank1: return .shortTrimBank1
        case .longTermFuelTrimBank1: return .longTrimBank1
        case .shortTermFuelTrimBank2: return .shortTrimBank2
        case .longTermFuelTrimBank2: return .longTrimBank2
        default: return nil
        }
    }

    private static func displayValue(_ value: Double, for metric: DemoMetric) -> Double {
        switch metric {
        case .vehicleSpeed: return value / 1.609344
        case .coolant: return value * 9 / 5 + 32
        default: return value
        }
    }
}
