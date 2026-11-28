import DiagnosticsCore
import SwiftUI

enum TransmissionGauge: String, CaseIterable, Identifiable {
    case atf, engine, input, output

    var id: String { "transmission-gauge-\(rawValue)" }
    var unit: String { self == .atf ? "°F" : "rpm" }

    var label: (title: String, icon: String) {
        switch self {
        case .atf: ("ATF temperature", "thermometer.medium")
        case .engine: ("Engine speed", "gauge.with.dots.needle.33percent")
        case .input: ("Input shaft speed", "arrow.right.to.line")
        case .output: ("Output shaft speed", "arrow.right")
        }
    }

    func display(_ readings: HondaTransmissionReadings) -> String {
        switch self {
        case .atf:
            let fahrenheit = Double(readings.atfCelsius) * 9 / 5 + 32
            return fahrenheit.formatted(.number.precision(.fractionLength(0...1)))
        case .engine: return readings.engineRPM.formatted()
        case .input: return readings.inputRPM.formatted()
        case .output: return readings.outputRPM.formatted()
        }
    }
}

struct TransmissionGaugesView: View {
    let capture: HondaTransmissionCapture?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible())]
        } else {
            [GridItem(.adaptive(minimum: 135), spacing: 10)]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transmission gauges")
                    .font(.headline)

                Text("Honda reference · scan snapshot")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(GarageTheme.mutedText)

                if let capture, capture.readings != nil {
                    let capturedTime = capture.capturedAt.formatted(date: .abbreviated, time: .standard)
                    Text("Scan completed \(capturedTime)")
                        .font(.caption)
                        .foregroundStyle(GarageTheme.mutedText)
                } else {
                    Text("Run a transmission scan to populate these gauges.")
                        .font(.caption)
                        .foregroundStyle(GarageTheme.mutedText)
                }
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(TransmissionGauge.allCases) { metric in
                    gauge(metric, value: (capture?.readings).map(metric.display))
                }
            }
        }
    }

    private func gauge(_ metric: TransmissionGauge, value: String?) -> some View {
        let label = metric.label
        let unit = metric.unit
        return VStack(alignment: .leading, spacing: 8) {
            Label(label.title, systemImage: label.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(GarageTheme.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let value {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        gaugeValue(value)
                        gaugeUnit(unit)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        gaugeValue(value)
                        gaugeUnit(unit)
                    }
                }
            } else {
                Text("Unavailable")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(GarageTheme.backdrop, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(GarageTheme.stroke)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.title)
        .accessibilityValue(value.map { "\($0) \(unit)" } ?? "Unavailable")
        .accessibilityIdentifier(metric.id)
    }

    private func gaugeValue(_ value: String) -> some View {
        Text(value)
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(GarageTheme.accent)
    }

    private func gaugeUnit(_ unit: String) -> some View {
        Text(unit)
            .font(.caption)
            .foregroundStyle(GarageTheme.mutedText)
    }
}
