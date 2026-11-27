import Foundation
import SwiftUI

struct FIXDScanResultView: View {
    let snapshot: FIXDScanSnapshot

    var body: some View {
        Section("Vehicle Connection") {
            Label("Live OBD-II snapshot", systemImage: "waveform.path")
                .font(.headline)
            Text(snapshot.vehicleProtocol)
            Text("Responding ECUs: " + snapshot.responders.joined(separator: ", "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(snapshot.capturedAt, format: .dateTime.month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)

            ShareLink(item: snapshot.shareText, subject: Text("Vehicle scan report")) {
                Label("Share Vehicle Scan", systemImage: "square.and.arrow.up")
            }
        }

        Section("Vehicle Readings") {
            if snapshot.readings.isEmpty {
                Text("No supported live readings were returned.")
                    .foregroundStyle(.secondary)
            }

            ForEach(snapshot.readings) { sample in
                LabeledContent {
                    Text("\(sample.value, format: .number.precision(.fractionLength(0...2))) \(sample.unit)")
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sample.title)
                        Text("ECU " + sample.ecu)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !snapshot.unavailableReadings.isEmpty {
                DisclosureGroup("Unavailable readings") {
                    ForEach(snapshot.unavailableReadings, id: \.self) { name in
                        Text(name)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        ForEach(snapshot.troubleCodes) { group in
            Section(group.title) {
                if let status = group.status {
                    Text(status)
                        .foregroundStyle(.secondary)
                }
                ForEach(group.ecus) { ecu in
                    LabeledContent("ECU " + ecu.id) {
                        if let unavailable = ecu.unavailableReason {
                            Text(unavailable)
                                .foregroundStyle(.secondary)
                        } else if ecu.codes.isEmpty {
                            Text("No codes returned")
                                .foregroundStyle(.secondary)
                        } else {
                            VehicleTroubleCodeList(codes: ecu.codes)
                        }
                    }
                }
            }
        }
    }
}

private extension FIXDScanSnapshot {
    var shareText: String {
        var lines = [
            "Read-Only Vehicle Scan",
            "Captured: \(capturedAt.ISO8601Format())",
            "Protocol: \(vehicleProtocol)",
            "Responding ECUs: " + responders.joined(separator: ", "),
        ]
        for reading in readings {
            let value = reading.value.formatted(.number.precision(.fractionLength(0...2)))
            lines.append("ECU \(reading.ecu) · \(reading.title): \(value) \(reading.unit)")
        }
        for group in troubleCodes {
            lines.append(group.title)
            if let status = group.status { lines.append(status) }
            for ecu in group.ecus {
                let codes = ecu.codes.isEmpty ? "No codes returned" : ecu.codes.joined(separator: ", ")
                lines.append("ECU \(ecu.id): " + (ecu.unavailableReason ?? codes))
                for code in ecu.codes {
                    if let description = MDXTroubleCode.description(for: code) {
                        lines.append("2011 MDX reference · \(code): \(description)")
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}

struct VehicleTroubleCodeList: View {
    let codes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(codes, id: \.self) { code in
                VStack(alignment: .leading, spacing: 3) {
                    Text(code).monospaced()
                    if let description = MDXTroubleCode.description(for: code) {
                        Text("2011 MDX · " + description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}
