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
                            Text(ecu.codes.joined(separator: ", "))
                                .monospaced()
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
