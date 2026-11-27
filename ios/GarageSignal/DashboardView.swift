import SwiftUI

@MainActor
struct DashboardView: View {
    @ObservedObject var telemetry: DemoTelemetry
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
                SourceLabel(title: "Simulated telemetry")
                Text("2011 Acura MDX")
                    .font(.title2.bold())
                Text("3.7L · SH-AWD")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
            }
            if let primary = metrics.first {
                MetricCard(metric: primary, samples: telemetry.samples, prominent: true)
            }
            if metrics.count > 1 {
                LazyVGrid(columns: gaugeColumns, spacing: 10) {
                    ForEach(metrics.dropFirst()) { metric in
                        MetricCard(metric: metric, samples: telemetry.samples)
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
            }
        }
        .sheet(isPresented: $editing) {
            GaugePicker(metrics: metrics) { selection in
                storedMetrics = selection.map(\.rawValue).joined(separator: ",")
            }
        }
    }
}

private struct MetricCard: View {
    let metric: DemoMetric
    let samples: [DemoSample]
    var prominent = false

    var body: some View {
        let readings = samples.map { $0[metric] }
        let display = readings.last.map(metric.display) ?? "—"

        GaragePanel {
            VStack(alignment: .leading, spacing: prominent ? 12 : 9) {
                Label(metric.title, systemImage: metric.icon)
                    .font(prominent ? .subheadline.weight(.semibold) : .footnote.weight(.medium))
                    .foregroundStyle(GarageTheme.mutedText)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        valueText(display)
                        unitText
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        valueText(display)
                        unitText
                    }
                }
                TrendPlot(readings: readings, range: metric.displayRange)
                    .frame(height: prominent ? 78 : 31)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue("Simulated, \(display) \(metric.unit)")
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
