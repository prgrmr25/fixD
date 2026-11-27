import Combine
import Foundation

enum DemoMetric: String, CaseIterable, Identifiable {
    case engineSpeed = "engine_rpm"
    case vehicleSpeed = "vehicle_mph"
    case coolant = "coolant_f"
    case ignition = "ignition_advance_deg"
    case throttle = "throttle_pct"
    case voltage = "module_voltage_v"
    case load = "engine_load_pct"
    case shortTrimBank1 = "short_fuel_trim_bank_1_pct"
    case shortTrimBank2 = "short_fuel_trim_bank_2_pct"
    case longTrimBank1 = "long_fuel_trim_bank_1_pct"
    case longTrimBank2 = "long_fuel_trim_bank_2_pct"

    static let dashboardDefaults: [Self] = [
        .engineSpeed, .vehicleSpeed, .coolant, .ignition, .throttle, .voltage,
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .engineSpeed: "Engine speed"
        case .vehicleSpeed: "Vehicle speed"
        case .coolant: "Coolant temperature"
        case .ignition: "Ignition advance"
        case .throttle: "Throttle position"
        case .voltage: "Module voltage"
        case .load: "Engine load"
        case .shortTrimBank1: "Short-term fuel trim · B1"
        case .shortTrimBank2: "Short-term fuel trim · B2"
        case .longTrimBank1: "Long-term fuel trim · B1"
        case .longTrimBank2: "Long-term fuel trim · B2"
        }
    }

    var icon: String {
        switch self {
        case .engineSpeed: "gauge.with.dots.needle.67percent"
        case .vehicleSpeed: "speedometer"
        case .coolant: "thermometer.medium"
        case .ignition: "bolt"
        case .throttle: "slider.horizontal.3"
        case .voltage: "battery.75percent"
        case .load: "chart.bar"
        case .shortTrimBank1, .shortTrimBank2, .longTrimBank1, .longTrimBank2: "fuelpump"
        }
    }

    var unit: String {
        switch self {
        case .engineSpeed: "rpm"
        case .vehicleSpeed: "mph"
        case .coolant: "°F"
        case .ignition: "°"
        case .voltage: "V"
        case .throttle, .load, .shortTrimBank1, .shortTrimBank2, .longTrimBank1, .longTrimBank2: "%"
        }
    }

    var precision: Int {
        switch self {
        case .voltage, .shortTrimBank1, .shortTrimBank2, .longTrimBank1, .longTrimBank2: 1
        default: 0
        }
    }

    var displayRange: ClosedRange<Double> {
        switch self {
        case .engineSpeed: 600...3500
        case .vehicleSpeed: 0...80
        case .coolant: 150...215
        case .ignition: -5...45
        case .throttle, .load: 0...100
        case .voltage: 12...15
        case .shortTrimBank1, .shortTrimBank2, .longTrimBank1, .longTrimBank2: -15...15
        }
    }

    func display(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(precision)))
    }
}

struct DemoSample {
    let timestamp: Date
    private let values: [DemoMetric: Double]

    init(timestamp: Date, elapsed: TimeInterval) {
        self.timestamp = timestamp
        let motion = (sin(elapsed / 10 + 0.6) + 1) / 2
        let pedal = (sin(elapsed / 3.7) + 1) / 2
        let temperature = 181 + 13 * (1 - exp(-elapsed / 38))
        values = [
            .engineSpeed: 730 + motion * (1350 + 540 * pedal),
            .vehicleSpeed: 61 * motion,
            .coolant: temperature + 1.3 * sin(elapsed / 9),
            .ignition: 11 + 18 * motion + 4 * sin(elapsed / 2.6),
            .throttle: 6 + 37 * motion * pedal,
            .voltage: 14.15 + 0.21 * sin(elapsed / 5),
            .load: 18 + 57 * motion * pedal,
            .shortTrimBank1: -1.4 + 5.5 * sin(elapsed / 4),
            .shortTrimBank2: -0.2 + 4.5 * sin(elapsed / 4 + 0.5),
            .longTrimBank1: -2.1 + 0.6 * sin(elapsed / 22),
            .longTrimBank2: 1.8 + 0.7 * sin(elapsed / 24),
        ]
    }

    subscript(metric: DemoMetric) -> Double {
        values[metric, default: 0]
    }
}

@MainActor
final class DemoTelemetry: ObservableObject {
    @Published private(set) var samples: [DemoSample]
    private let startedAt: Date
    private let sampleLimit = 60

    init() {
        startedAt = .now
        samples = [DemoSample(timestamp: startedAt, elapsed: 0)]
    }

    func update(at timestamp: Date) -> DemoSample {
        let elapsed = max(0, timestamp.timeIntervalSince(startedAt))
        let sample = DemoSample(timestamp: timestamp, elapsed: elapsed)
        samples.append(sample)
        if samples.count > sampleLimit {
            samples.removeFirst(samples.count - sampleLimit)
        }
        return sample
    }
}
