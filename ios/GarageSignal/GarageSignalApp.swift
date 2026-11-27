import SwiftUI

@main
@MainActor
struct GarageSignalApp: App {
    private enum AppTab: Hashable {
        case dashboard
        case signals
        case diagnostics
        case logs
    }

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var telemetry = DemoTelemetry()
    @StateObject private var logs = DriveLogStore()
    @StateObject private var bridge = BluetoothBridge()
    @State private var selectedTab: AppTab = .dashboard
    @State private var diagnosticsPath: [DiagnosticRoute] = []

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    DashboardView(
                        telemetry: telemetry,
                        vehicle: bridge.vehicle,
                        onConnect: openAdapter,
                        onStop: bridge.stopVehicleReadings
                    )
                }
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.33percent") }
                .tag(AppTab.dashboard)

                NavigationStack {
                    SignalCatalogView(telemetry: telemetry, vehicle: bridge.vehicle)
                }
                .tabItem { Label("Signals", systemImage: "list.bullet") }
                .tag(AppTab.signals)

                NavigationStack(path: $diagnosticsPath) {
                    DiagnosticsView()
                        .navigationDestination(for: DiagnosticRoute.self) { route in
                            switch route {
                            case .adapter:
                                AdapterInspectorView(bridge: bridge)
                            case .modules:
                                ModuleCatalogView(
                                    vehicle: bridge.vehicle,
                                    bridge: bridge,
                                    onOpenAdapter: openAdapter
                                )
                            case .serviceFunctions:
                                ServiceFunctionsView()
                            }
                        }
                }
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                .tag(AppTab.diagnostics)

                NavigationStack {
                    LogsView(logs: logs)
                }
                .tabItem { Label("Drive Logs", systemImage: "waveform.path") }
                .tag(AppTab.logs)
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
                    bridge.close()
                    logs.stop()
                }
            }
        }
    }

    private func openAdapter() {
        selectedTab = .diagnostics
        diagnosticsPath = [.adapter]
    }
}
