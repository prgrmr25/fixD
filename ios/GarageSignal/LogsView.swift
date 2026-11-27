import SwiftUI

@MainActor
struct LogsView: View {
    @ObservedObject var logs: DriveLogStore

    var body: some View {
        GarageScreen {
            recordingPanel

            if let error = logs.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.warning)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Saved CSV files")
                    .font(.title2.bold())

                if logs.savedLogs.isEmpty {
                    Text("Record a demo session to create your first CSV.")
                        .font(.subheadline)
                        .foregroundStyle(GarageTheme.mutedText)
                }
                ForEach(logs.savedLogs) { entry in
                    logPanel(entry)
                }
            }
        }
        .navigationTitle("Drive Logs")
    }

    private var recordingPanel: some View {
        GaragePanel {
            VStack(alignment: .leading, spacing: 12) {
                SourceLabel(title: "Simulated telemetry")
                if let recording = logs.recording {
                    Label("Recording demo", systemImage: "record.circle")
                        .font(.headline)
                        .foregroundStyle(GarageTheme.accent)
                    Text("\(recording.sampleCount) samples saved")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(GarageTheme.mutedText)
                    Button {
                        logs.stop()
                    } label: {
                        Label("Stop and save", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Record a demo session")
                        .font(.headline)
                    Text("Saves one simulated sample per second on this device. Recording ends if the app goes to the background.")
                        .font(.subheadline)
                        .foregroundStyle(GarageTheme.mutedText)
                    Button {
                        logs.start()
                    } label: {
                        Label("Start recording", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func logPanel(_ entry: SavedDemoLog) -> some View {
        GaragePanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)
                Text("Simulated drive · \(ByteCountFormatter.string(fromByteCount: Int64(entry.fileSize), countStyle: .file))")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
                ShareLink(item: entry.url) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
