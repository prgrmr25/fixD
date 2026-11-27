import SwiftUI

@main
@MainActor
struct GarageSignalApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = DemoTelemetry()
    @StateObject private var logs = DriveLogStore()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    DashboardView(telemetry: telemetry)
                }
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }

                NavigationStack {
                    DiagnosticsView()
                }
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

                NavigationStack {
                    LogsView(logs: logs)
                }
                .tabItem { Label("Drive Logs", systemImage: "waveform.path") }
            }
            .tint(GarageTheme.accent)
            .preferredColorScheme(.dark)
            .task {
                while !Task.isCancelled {
                    let sample = telemetry.update(at: .now)
                    logs.append(sample)
                    do {
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    logs.stop()
                }
            }
        }
    }
}
