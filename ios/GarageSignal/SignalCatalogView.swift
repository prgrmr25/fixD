import DiagnosticsCore
import SwiftUI

@MainActor
struct SignalCatalogView: View {
    @ObservedObject var telemetry: DemoTelemetry
    @ObservedObject var vehicle: VehicleTelemetry
    let misfireSnapshot: FIXDMisfireSnapshot?

    @AppStorage("telemetry.source.v1") private var source: TelemetrySource = .vehicle
    @State private var query = ""

    private var matchingGroups: [SignalGroup] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return SignalGroup.catalog }
        return SignalGroup.catalog.compactMap { group in
            let matches = group.signals.filter { signal in
                let searchable = [group.title, signal.title, signal.unit, signal.keywords]
                    .joined(separator: " ")
                return terms.allSatisfy { searchable.localizedStandardContains(String($0)) }
            }
            return matches.isEmpty ? nil : SignalGroup(title: group.title, signals: matches)
        }
    }

    var body: some View {
        let groups = matchingGroups

        List {
            if !groups.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        TelemetrySourcePicker(source: $source)
                        Text("2011 Acura MDX · 3.7L SH-AWD profile")
                            .font(.subheadline.weight(.semibold))
                        if source == .demo {
                            SourceLabel(title: "Simulated telemetry")
                        } else {
                            VehicleTelemetryStatus(
                                isMonitoring: vehicle.isMonitoring,
                                isAdapterConnected: vehicle.isAdapterConnected,
                                lastUpdated: vehicle.lastUpdated
                            )
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(GarageTheme.surface)
                }
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.signals) { signal in
                        SignalRow(signal: signal, values: values(for: signal))
                            .listRowBackground(GarageTheme.surface)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(GarageTheme.backdrop)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationTitle("Signals")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a signal")
    }

    private func values(for signal: SignalDefinition) -> [SignalValue] {
        switch source {
        case .demo:
            guard let metric = signal.metric, let sample = telemetry.samples.last else { return [] }
            return [SignalValue(text: metric.display(sample[metric]), source: "Demo")]
        case .vehicle:
            if let cylinder = signal.misfireCylinder {
                guard let snapshot = misfireSnapshot, let count = snapshot.countsByCylinder[cylinder] else { return [] }
                let time = snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened)
                return [.init(text: count.formatted(), source: "ECU \(snapshot.ecu) · Mode 06 · \(time)")]
            }
            let readings: [VehicleTelemetry.Reading]
            if let vehiclePID = signal.vehiclePID {
                readings = vehicle.readings(forPID: vehiclePID)
            } else if let metric = signal.metric {
                readings = vehicle.readings(for: metric)
            } else {
                return []
            }
            let scanDate = signal.vehiclePID?.isScanOnlyMeasurement == true ? vehicle.lastScanOnlyUpdated : nil
            let scanTime = scanDate?.formatted(date: .abbreviated, time: .shortened)
            return readings.map { reading in
                let ecu = "ECU \(reading.ecu)"
                let source = scanTime.map { "\(ecu) · Scan \($0)" } ?? ecu
                return SignalValue(text: signal.display(reading.value), source: source)
            }
        }
    }
}

private struct SignalValue: Identifiable {
    let text: String
    let source: String

    var id: String { source }
}

private struct SignalRow: View {
    let signal: SignalDefinition
    let values: [SignalValue]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var emptyValueNote: String? {
        guard values.isEmpty else { return nil }
        if signal.misfireCylinder != nil { return "Read in Engine and PCM." }
        if signal.vehiclePID?.isScanOnlyMeasurement == true { return "Read during vehicle scans." }
        return nil
    }

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            VStack(alignment: .leading, spacing: 3) {
                Text(signal.title)
                    .font(.subheadline.weight(.medium))
                if let note = signal.note ?? emptyValueNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(GarageTheme.mutedText)
                }
            }
            if !stacked {
                Spacer(minLength: 3)
            }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 6) {
                if values.isEmpty {
                    Text("Unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GarageTheme.mutedText)
                    if !signal.unit.isEmpty {
                        Text(signal.unit)
                            .font(.caption2)
                            .foregroundStyle(GarageTheme.mutedText)
                    }
                }
                ForEach(values) { reading in
                    VStack(alignment: stacked ? .leading : .trailing, spacing: 3) {
                        Text("\(reading.text) \(signal.unit)")
                            .font(.subheadline.monospacedDigit())
                        Text(reading.source)
                            .font(.caption.monospaced())
                            .foregroundStyle(GarageTheme.accent)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(signal.id)
    }
}

private struct SignalDefinition: Identifiable {
    let title: String
    let unit: String
    let keywords: String
    let metric: DemoMetric?
    let note: String?
    let vehiclePID: CurrentDataPID?
    let misfireCylinder: Int?

    var id: String { title }

    init(
        _ title: String,
        unit: String = "",
        keywords: String = "",
        note: String? = nil,
        vehiclePID: CurrentDataPID? = nil,
        misfireCylinder: Int? = nil
    ) {
        self.title = title
        self.unit = unit
        self.keywords = keywords
        metric = nil
        self.note = note
        self.vehiclePID = vehiclePID
        self.misfireCylinder = misfireCylinder
    }

    init(_ metric: DemoMetric, keywords: String = "") {
        title = metric.title
        unit = metric.unit
        self.keywords = keywords
        self.metric = metric
        note = nil
        vehiclePID = nil
        misfireCylinder = nil
    }

    func display(_ value: Double) -> String {
        if let metric { return metric.display(value) }
        let decimalPlaces = vehiclePID == .massAirFlow ? 2 : 0
        return value.formatted(.number.precision(.fractionLength(decimalPlaces)))
    }
}

private struct SignalGroup: Identifiable {
    let title: String
    let signals: [SignalDefinition]

    var id: String { title }

    static let catalog: [Self] = [
        Self(title: "Engine and lubrication", signals: [
            .init(.engineSpeed, keywords: "rpm revolutions idle"),
            .init(
                "Engine oil pressure", unit: "psi", keywords: "lubrication oil gauge",
                note: "No verified numeric pressure PID for this vehicle."
            ),
            .init(
                "Oil pressure warning switch", unit: "On/Off", keywords: "lubrication warning light",
                note: "Main low-oil-pressure warning. FIXD read unverified."
            ),
            .init(
                "VTEC oil-pressure switch", unit: "On/Off", keywords: "rocker arm valve timing vtec pres sw",
                note: "Rocker-arm switch in Honda HDS. FIXD read unverified."
            ),
            .init(
                "Engine oil temperature", unit: "°F", keywords: "lubrication temp",
                vehiclePID: .engineOilTemperature
            ),
            .init(.load),
            .init(.ignition, keywords: "spark timing advance"),
            .init("Knock correction", unit: "°", keywords: "ignition retard detonation"),
            .init("Cylinder 1 misfire count", unit: "Count", misfireCylinder: 1),
            .init("Cylinder 2 misfire count", unit: "Count", misfireCylinder: 2),
            .init("Cylinder 3 misfire count", unit: "Count", misfireCylinder: 3),
            .init("Cylinder 4 misfire count", unit: "Count", misfireCylinder: 4),
            .init("Cylinder 5 misfire count", unit: "Count", misfireCylinder: 5),
            .init("Cylinder 6 misfire count", unit: "Count", misfireCylinder: 6),
        ]),
        Self(title: "Air, fuel, and emissions", signals: [
            .init(.throttle, keywords: "TPS ETCS electronic throttle"),
            .init("Accelerator pedal position", unit: "%", keywords: "APP"),
            .init(
                "Intake manifold absolute pressure", unit: "kPa", keywords: "MAP vacuum",
                vehiclePID: .intakeManifoldAbsolutePressure
            ),
            .init(
                "Intake air temperature", unit: "°F", keywords: "IAT temp",
                vehiclePID: .intakeAirTemperature
            ),
            .init("Mass air flow", unit: "g/s", keywords: "MAF airflow", vehiclePID: .massAirFlow),
            .init("Barometric pressure", unit: "kPa", keywords: "BARO", vehiclePID: .barometricPressure),
            .init("Commanded equivalence ratio", unit: "Ratio", keywords: "mixture AFR lambda"),
            .init("Upstream air/fuel sensor · B1", unit: "λ", keywords: "bank 1 sensor 1 A/F lambda AFR O2"),
            .init("Upstream air/fuel sensor · B2", unit: "λ", keywords: "bank 2 sensor 1 A/F lambda AFR O2"),
            .init("Downstream oxygen sensor · B1", unit: "V", keywords: "bank 1 sensor 2 O2"),
            .init("Downstream oxygen sensor · B2", unit: "V", keywords: "bank 2 sensor 2 O2"),
            .init(.shortTrimBank1, keywords: "STFT bank 1"),
            .init(.shortTrimBank2, keywords: "STFT bank 2"),
            .init(.longTrimBank1, keywords: "LTFT bank 1"),
            .init(.longTrimBank2, keywords: "LTFT bank 2"),
            .init("Fuel system loop status", unit: "State", keywords: "open loop closed loop"),
            .init("Fuel pressure", unit: "psi"),
            .init("Fuel tank level", unit: "%", keywords: "gasoline"),
            .init("EVAP purge command", unit: "%", keywords: "evaporative purge duty"),
        ]),
        Self(title: "Cooling", signals: [
            .init(.coolant, keywords: "ECT engine temperature temp"),
            .init("Secondary coolant temperature", unit: "°F", keywords: "ECT2 temp"),
            .init("Cooling fan command", unit: "State", keywords: "radiator fan"),
        ]),
        Self(title: "Transmission and torque converter", signals: [
            .init(.vehicleSpeed, keywords: "VSS road speed"),
            .init("Transmission fluid temperature", unit: "°F", keywords: "ATF TFT temp"),
            .init("Selected gear", unit: "Position", keywords: "shift selector"),
            .init("Current gear", unit: "Gear", keywords: "actual gear shift"),
            .init("Transmission input shaft speed", unit: "rpm", keywords: "turbine ISS"),
            .init("Transmission output shaft speed", unit: "rpm", keywords: "OSS"),
            .init("Torque converter clutch command", unit: "State", keywords: "TCC lockup"),
            .init("Torque converter clutch slip", unit: "rpm", keywords: "TCC lockup slip"),
            .init("Torque converter clutch duty", unit: "%", keywords: "TCC lockup duty cycle"),
        ]),
        Self(title: "SH-AWD and chassis", signals: [
            .init("SH-AWD operating state", unit: "State", keywords: "AWD differential all wheel drive"),
            .init("Rear differential fluid temperature", unit: "°F", keywords: "AWD temp"),
            .init("Rear differential torque command", unit: "N·m", keywords: "AWD torque split"),
            .init("Left front wheel speed", unit: "mph", keywords: "ABS LF"),
            .init("Right front wheel speed", unit: "mph", keywords: "ABS RF"),
            .init("Left rear wheel speed", unit: "mph", keywords: "ABS LR"),
            .init("Right rear wheel speed", unit: "mph", keywords: "ABS RR"),
            .init("Steering angle", unit: "°", keywords: "VSA stability"),
            .init("Brake pedal switch", unit: "State", keywords: "brake VSA"),
        ]),
        Self(title: "Electrical", signals: [
            .init(.voltage, keywords: "battery charging PCM ECU volts"),
            .init("Battery current", unit: "A", keywords: "amps charging"),
            .init("Charging command", unit: "%", keywords: "alternator generator"),
        ]),
        Self(title: "Codes and readiness", signals: [
            .init("Malfunction indicator lamp", unit: "State", keywords: "MIL check engine light CEL"),
            .init("Confirmed trouble codes", unit: "Count", keywords: "stored DTC"),
            .init("Pending trouble codes", unit: "Count", keywords: "pending DTC"),
            .init("Permanent trouble codes", unit: "Count", keywords: "permanent DTC"),
            .init("Misfire monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Fuel system monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Comprehensive component monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Catalyst monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Oxygen sensor monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Oxygen sensor heater monitor", unit: "Status", keywords: "I/M emission readiness"),
            .init("Evaporative system monitor", unit: "Status", keywords: "EVAP I/M emission readiness"),
        ]),
    ]
}
