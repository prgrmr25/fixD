import SwiftUI

@MainActor
struct DashboardView: View {
    @ObservedObject var telemetry: DemoTelemetry
    @ObservedObject var vehicle: VehicleTelemetry
    let onConnect: () -> Void
    let onStop: () -> Void

    @AppStorage("telemetry.source.v1") private var source: TelemetrySource = .vehicle
    @AppStorage("dashboard.metrics.v1") private var storedMetrics =
        DemoMetric.dashboardDefaults.map(\.rawValue).joined(separator: ",")
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editing = false

    private var metrics: [DemoMetric] {
        let decoded = storedMetrics.split(separator: ",").compactMap {
            DemoMetric(rawValue: String($0))
        }
        var seen: Set<DemoMetric> = []
        let unique = decoded.filter { seen.insert($0).inserted }
        return unique.isEmpty ? DemoMetric.dashboardDefaults : unique
    }

    private var gaugeColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 146), spacing: 10)]
    }

    var body: some View {
        GarageScreen {
            VStack(alignment: .leading, spacing: 5) {
                Text("2011 Acura MDX")
                    .font(.title2.bold())
                Text("3.7L · SH-AWD profile")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
            }
            GaragePanel {
                VStack(alignment: .leading, spacing: 12) {
                    TelemetrySourcePicker(source: $source)
                    if source == .demo {
                        SourceLabel(title: "Simulated telemetry")
                    } else {
                        VehicleTelemetryStatus(
                            isMonitoring: vehicle.isMonitoring,
                            lastUpdated: vehicle.lastUpdated
                        )
                        if vehicle.isMonitoring {
                            Button("Stop monitoring", systemImage: "stop.circle", action: onStop)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("stop-vehicle-monitoring")
                        } else {
                            Button("Connect to vehicle", systemImage: "antenna.radiowaves.left.and.right", action: onConnect)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("connect-vehicle")
                        }
                    }
                }
            }
            if let primary = metrics.first {
                gauge(primary, prominent: true)
            }
            if metrics.count > 1 {
                LazyVGrid(columns: gaugeColumns, spacing: 10) {
                    ForEach(metrics.dropFirst()) { metric in
                        gauge(metric)
                    }
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = true
                } label: {
                    Label("Edit gauges", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("edit-gauges")
            }
        }
        .sheet(isPresented: $editing) {
            GaugePicker(metrics: metrics) { selection in
                storedMetrics = selection.map(\.rawValue).joined(separator: ",")
            }
        }
    }

    private func gauge(_ metric: DemoMetric, prominent: Bool = false) -> some View {
        let channels: [MetricChannel]
        switch source {
        case .demo:
            let history = telemetry.samples.map { $0[metric] }
            channels = history.last.map { [MetricChannel(ecu: nil, value: $0, history: history)] } ?? []
        case .vehicle:
            channels = vehicle.readings(for: metric).map { reading in
                MetricChannel(
                    ecu: reading.ecu,
                    value: reading.value,
                    history: vehicle.history(for: metric, ecu: reading.ecu)
                )
            }
        }
        return MetricCard(metric: metric, channels: channels, prominent: prominent)
    }
}

struct TelemetrySourcePicker: View {
    @Binding var source: TelemetrySource

    var body: some View {
        Picker("Telemetry source", selection: $source) {
            Text("Vehicle").tag(TelemetrySource.vehicle)
            Text("Demo").tag(TelemetrySource.demo)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("telemetry-source")
    }
}

struct VehicleTelemetryStatus: View {
    let isMonitoring: Bool
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isMonitoring {
                SourceLabel(title: "Vehicle monitoring active")
            } else {
                Label("Vehicle monitoring inactive", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GarageTheme.mutedText)
            }
            if let lastUpdated {
                let timestamp = lastUpdated.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
                Text(isMonitoring ? "Latest reading \(timestamp)" : "Last vehicle scan \(timestamp)")
                    .font(.caption)
                    .foregroundStyle(GarageTheme.mutedText)
            } else {
                Text(isMonitoring ? "Waiting for vehicle readings." : "Connect the adapter and start a read-only scan.")
                    .font(.caption)
                    .foregroundStyle(GarageTheme.mutedText)
            }
        }
    }
}

private struct MetricChannel: Identifiable {
    let ecu: String?
    let value: Double
    let history: [Double]

    var id: String { ecu ?? "demo" }
}

private struct MetricCard: View {
    let metric: DemoMetric
    let channels: [MetricChannel]
    var prominent = false

    private var accessibilityReading: String {
        guard !channels.isEmpty else { return "Unavailable" }
        return channels.map { channel in
            let label = channel.ecu.map { "ECU \($0)" } ?? "Simulated"
            return "\(label), \(metric.display(channel.value)) \(metric.unit)"
        }.joined(separator: ". ")
    }

    private var chartRange: ClosedRange<Double> {
        let history = channels.flatMap(\.history)
        let low = min(metric.displayRange.lowerBound, history.min() ?? metric.displayRange.lowerBound)
        let high = max(metric.displayRange.upperBound, history.max() ?? metric.displayRange.upperBound)
        return low...high
    }

    var body: some View {
        GaragePanel {
            VStack(alignment: .leading, spacing: prominent ? 12 : 9) {
                Label(metric.title, systemImage: metric.icon)
                    .font(prominent ? .subheadline.weight(.semibold) : .footnote.weight(.medium))
                    .foregroundStyle(GarageTheme.mutedText)
                if channels.isEmpty {
                    Text("Unavailable")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(GarageTheme.mutedText)
                }
                ForEach(channels) { channel in
                    if channel.id != channels.first?.id {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if let ecu = channel.ecu {
                            Text("ECU \(ecu)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(GarageTheme.mutedText)
                        }
                        value(channel.value)
                        if channel.history.count > 1 {
                            TrendPlot(readings: channel.history, range: chartRange)
                                .frame(height: prominent ? 78 : 31)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(accessibilityReading)
    }

    private func value(_ reading: Double) -> some View {
        let display = metric.display(reading)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                valueText(display)
                unitText
            }
            VStack(alignment: .leading, spacing: 2) {
                valueText(display)
                unitText
            }
        }
    }

    private func valueText(_ display: String) -> some View {
        Text(display)
            .font(prominent ? .largeTitle.weight(.semibold) : .title3.weight(.semibold))
            .monospacedDigit()
            .fixedSize()
    }

    private var unitText: some View {
        Text(metric.unit)
            .font(.caption.weight(.semibold))
            .foregroundStyle(GarageTheme.accent)
    }
}

private struct TrendPlot: View {
    let readings: [Double]
    let range: ClosedRange<Double>

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                Path { path in
                    for fraction in [0.2, 0.5, 0.8] {
                        let y = geometry.size.height * CGFloat(fraction)
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(GarageTheme.stroke, style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            TrendPath(readings: readings, scale: range)
                .stroke(
                    GarageTheme.accent,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
                .padding(.vertical, 2)
        }
    }
}

private struct TrendPath: Shape {
    let readings: [Double]
    let scale: ClosedRange<Double>

    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = rect.width / CGFloat(max(1, readings.count - 1))
            for (index, point) in readings.enumerated() {
                let fraction = (point - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
                let y = rect.maxY - rect.height * CGFloat(min(1, max(0, fraction)))
                let coordinate = CGPoint(x: rect.minX + width * CGFloat(index), y: y)
                if index == 0 {
                    path.move(to: coordinate)
                    if readings.count == 1 {
                        path.addLine(to: CGPoint(x: rect.maxX, y: y))
                    }
                } else {
                    path.addLine(to: coordinate)
                }
            }
        }
    }
}

private struct GaugePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<DemoMetric>
    private let save: ([DemoMetric]) -> Void

    init(metrics: [DemoMetric], save: @escaping ([DemoMetric]) -> Void) {
        _selected = State(initialValue: Set(metrics))
        self.save = save
    }

    var body: some View {
        NavigationStack {
            List(DemoMetric.allCases) { metric in
                Toggle(
                    isOn: Binding(
                        get: { selected.contains(metric) },
                        set: { enabled in
                            if enabled {
                                selected.insert(metric)
                            } else {
                                selected.remove(metric)
                            }
                        }
                    )
                ) {
                    Label(metric.title, systemImage: metric.icon)
                }
            }
            .navigationTitle("Dashboard gauges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save(DemoMetric.allCases.filter { selected.contains($0) })
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}
