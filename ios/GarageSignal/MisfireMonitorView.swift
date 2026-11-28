import SwiftUI

@MainActor
struct MisfireMonitorView: View {
    @ObservedObject private var bridge: BluetoothBridge
    @ObservedObject private var vehicle: VehicleTelemetry
    private let onOpenAdapter: () -> Void

    init(bridge: BluetoothBridge, onOpenAdapter: @escaping () -> Void) {
        _bridge = ObservedObject(wrappedValue: bridge)
        _vehicle = ObservedObject(wrappedValue: bridge.vehicle)
        self.onOpenAdapter = onOpenAdapter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Read-only drive-cycle snapshot", systemImage: "waveform.path")
                .font(.headline)
            Text("With the engine running, the ECU can report counts for the current drive cycle. Before startup, it may return counts from the previous drive cycle. Each read captures one snapshot.")
                .font(.subheadline)
                .foregroundStyle(GarageTheme.mutedText)
            Text("Park the vehicle before reading.")
                .font(.caption)
                .foregroundStyle(GarageTheme.mutedText)

            if vehicle.isAdapterConnected {
                Button("Read Misfire Counts", systemImage: "magnifyingglass", action: bridge.scanMisfires)
                    .buttonStyle(.borderedProminent)
                    .disabled(!bridge.canStartLiveScan)
                    .accessibilityIdentifier("read-misfire-counts")
                if vehicle.isMonitoring {
                    Text("Stop live readings before requesting a misfire snapshot.")
                        .font(.caption)
                        .foregroundStyle(GarageTheme.mutedText)
                }
            } else {
                Button("Connect to FIXD", systemImage: "antenna.radiowaves.left.and.right", action: onOpenAdapter)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("connect-misfire-fixd")
            }

            if let status = bridge.misfireScanStatus {
                Text(status)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("misfire-scan-status")
            }

            if let snapshot = bridge.misfireScanResult {
                Divider()
                snapshotPanel(snapshot)
            }

            if let report = bridge.misfireScanReport {
                ShareLink(item: report, subject: Text("Misfire scan report")) {
                    Label("Share Misfire Scan", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("share-misfire-scan")
            }
        }
    }

    private func snapshotPanel(_ snapshot: FIXDMisfireSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cylinder counts")
                .font(.headline)
            LabeledContent("Responding ECU", value: snapshot.ecu)
            LabeledContent(
                "Captured",
                value: snapshot.capturedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())
            )
            .foregroundStyle(GarageTheme.mutedText)

            ForEach(1...6, id: \.self) { cylinder in
                Divider()
                LabeledContent {
                    if let count = snapshot.countsByCylinder[cylinder] {
                        Text(count.formatted())
                            .monospacedDigit()
                    } else {
                        Text("Unavailable")
                            .foregroundStyle(GarageTheme.mutedText)
                    }
                } label: {
                    Text("Cylinder \(cylinder)")
                }
                .accessibilityIdentifier("misfire-cylinder-\(cylinder)")
            }
        }
        .font(.subheadline)
    }
}
