import DiagnosticsCore
import SwiftUI

private struct VehicleModule: Identifiable {
    let id: String
    let name: String
    let icon: String
    let detail: String
    let readings: [String]
    let serviceFunctions: [String]
    var probe: HondaModuleProbe? = nil

    static let powertrain: [VehicleModule] = [
        .init(
            id: "pcm", name: "Engine and PCM", icon: "engine.combustion",
            detail: "3.7 L V6 · PGM-FI powertrain control",
            readings: [
                "Factory PCM identification and calibration",
                "Honda/Acura knock correction", "Manufacturer-specific DTCs",
                "Freeze frame and monitor readiness"
            ],
            serviceFunctions: ["PCM learned-value reset", "Throttle position learn", "Idle learn"],
            probe: .powertrain
        ),
        .init(
            id: "transmission", name: "Automatic transmission", icon: "gearshape.2",
            detail: "Six-speed automatic · torque converter and lock-up clutch",
            readings: [
                "ATF temperature", "Current and commanded gear", "Mainshaft and countershaft RPM",
                "Torque converter clutch state", "Torque converter slip",
                "Transmission diagnostics and calibration identification"
            ],
            serviceFunctions: ["Transmission adaptation or relearn, where supported"],
            probe: .transmission
        ),
        .init(
            id: "shawd", name: "SH-AWD", icon: "car.side",
            detail: "Super Handling All-Wheel Drive · rear torque distribution",
            readings: [
                "SH-AWD DTCs", "Rear differential temperature, if exposed",
                "Left and right rear clutch command or current, if exposed",
                "Torque distribution data, if exposed"
            ],
            serviceFunctions: ["OEM SH-AWD function tests, where supported"],
            probe: .shawd
        ),
    ]

    static let otherSystems: [VehicleModule] = [
        .init(
            id: "vsa", name: "ABS and VSA", icon: "steeringwheel",
            detail: "Braking and vehicle stability",
            readings: ["Chassis DTCs", "Four wheel speeds", "Steering angle and yaw data, if exposed"],
            serviceFunctions: ["VSA sensor calibration, where supported"],
            probe: .absVSA
        ),
        .init(
            id: "srs", name: "SRS", icon: "person.crop.circle",
            detail: "Airbag and supplemental restraint diagnostics",
            readings: ["SRS DTCs", "Control unit identification, if exposed"],
            serviceFunctions: [],
            probe: .srs
        ),
        .init(
            id: "tpms", name: "TPMS", icon: "exclamationmark.circle",
            detail: "Tire pressure monitoring",
            readings: ["TPMS DTCs", "Per-wheel pressure and sensor state, if exposed"],
            serviceFunctions: ["Sensor registration, where supported"],
            probe: .tpms
        ),
        .init(
            id: "body", name: "Body and multiplex", icon: "car.rear",
            detail: "Body control, cluster and trim-dependent modules",
            readings: [
                "Body DTCs", "Battery voltage and body switch states, if exposed",
                "Instrument cluster identification, if exposed", "Parking assistance status, if equipped"
            ],
            serviceFunctions: [],
            probe: .instrumentCluster
        ),
        .init(
            id: "climate", name: "Climate control", icon: "thermometer.medium",
            detail: "HVAC diagnostics, where the module is accessible",
            readings: ["Climate DTCs", "Temperature sensors and actuator position, if exposed"],
            serviceFunctions: []
        ),
    ]
}

struct ModuleCatalogView: View {
    @ObservedObject var vehicle: VehicleTelemetry
    @ObservedObject var bridge: BluetoothBridge
    let onOpenAdapter: () -> Void

    var body: some View {
        GarageScreen {
            Text("2011 Acura MDX 3.7L SH-AWD")
                .font(.title2.bold())
            VehicleLinkPanel(vehicle: vehicle)
            section("Powertrain", modules: VehicleModule.powertrain)
            section("Other systems", modules: VehicleModule.otherSystems)
        }
        .navigationTitle("Vehicle modules")
    }

    private func section(_ title: String, modules: [VehicleModule]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            GaragePanel {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(modules) { module in
                        if module.id != modules.first?.id {
                            Divider()
                        }
                        NavigationLink {
                            ModuleDetailsView(
                                module: module,
                                vehicle: vehicle,
                                bridge: bridge,
                                onOpenAdapter: onOpenAdapter
                            )
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(module.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(module.detail)
                                        .font(.caption)
                                        .foregroundStyle(GarageTheme.mutedText)
                                }
                            } icon: {
                                Image(systemName: module.icon)
                                    .foregroundStyle(GarageTheme.accent)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(module.id)
                    }
                }
            }
        }
    }
}

private struct VehicleLinkPanel: View {
    @ObservedObject var vehicle: VehicleTelemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vehicle link").font(.headline)
            GaragePanel {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("FIXD adapter", value: vehicle.isAdapterConnected ? "Connected" : "Disconnected")
                    LabeledContent("Standard OBD-II", value: diagnosticStatus)
                    if !vehicle.responders.isEmpty {
                        LabeledContent(vehicle.isAdapterConnected ? "ECU responders" : "Last ECU responders",
                                       value: vehicle.responders.count.formatted())
                    }
                    if let updated = vehicle.lastUpdated {
                        LabeledContent("Last reading", value: updated.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.subheadline)
            }
        }
    }

    private var diagnosticStatus: String {
        if vehicle.isMonitoring { return "Monitoring" }
        if vehicle.lastUpdated != nil { return "Last readings available" }
        if vehicle.isAdapterConnected { return vehicle.responders.isEmpty ? "Awaiting vehicle response" : "Vehicle responded" }
        return "No vehicle data"
    }
}

private struct ModuleDetailsView: View {
    let module: VehicleModule
    @ObservedObject var vehicle: VehicleTelemetry
    @ObservedObject var bridge: BluetoothBridge
    let onOpenAdapter: () -> Void

    private var isEngine: Bool { module.id == "pcm" }

    var body: some View {
        GarageScreen {
            Text(module.detail)
                .font(.title3.bold())

            VehicleLinkPanel(vehicle: vehicle)

            section("Module status") {
                VStack(alignment: .leading, spacing: 6) {
                    if isEngine {
                        Text(vehicle.responders.isEmpty ? "Awaiting standard OBD-II data" : "Standard OBD-II responses received")
                            .font(.subheadline.weight(.semibold))
                    }
                    if module.probe == .transmission,
                       bridge.moduleProbeResult[.transmission]?.transmission != nil {
                        Text(vehicle.isAdapterConnected ? "Transmission responded" : "Last transmission response")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GarageTheme.accent)
                        Text("The response matches the Honda automatic transmission family. Vehicle-specific live data fields still need validation.")
                            .font(.caption)
                            .foregroundStyle(GarageTheme.mutedText)
                    } else {
                        Text("Vehicle support unverified")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(GarageTheme.warning)
                        Text(isEngine
                             ? "ECU labels identify standard OBD-II responders. The factory PCM identity is unverified."
                             : "\(module.name) identification and diagnostics require a verified module-specific response.")
                            .font(.caption)
                            .foregroundStyle(GarageTheme.mutedText)
                    }
                }
            }

            if let probe = module.probe {
                moduleScan(probe)
            }

            if isEngine {
                engineReadings
                section("Cylinder misfire monitor") {
                    MisfireMonitorView(bridge: bridge, onOpenAdapter: onOpenAdapter)
                }
                engineTroubleCodes
            }

            items(isEngine ? "Additional PCM diagnostics" : "Read-only diagnostics",
                  values: module.readings, status: "Awaiting vehicle validation")
            if !module.serviceFunctions.isEmpty {
                items("Service functions", values: module.serviceFunctions, status: "Unavailable")
            }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func moduleScan(_ probe: HondaModuleProbe) -> some View {
        section("\(probe.title) · read-only scan") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compares replies to targeted read-only requests and keeps a shareable report even if the adapter returns no data. Module identity and condition require separate verification.")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
                Text("Park the vehicle and turn the ignition on before scanning.")
                    .font(.caption)
                    .foregroundStyle(GarageTheme.mutedText)

                if vehicle.isAdapterConnected {
                    Button("Scan module", systemImage: "magnifyingglass") {
                        bridge.scanModule(probe)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!bridge.canStartModuleProbe)
                    .accessibilityIdentifier("scan-module")
                } else {
                    Button("Connect to FIXD", systemImage: "antenna.radiowaves.left.and.right", action: onOpenAdapter)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("connect-module-fixd")
                }

                if let status = bridge.moduleProbeStatus[probe] {
                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("module-scan-status")
                }
                if vehicle.isAdapterConnected && !bridge.canStartModuleProbe && vehicle.isMonitoring {
                    Text("Stop live readings before scanning this module.")
                        .font(.caption)
                        .foregroundStyle(GarageTheme.mutedText)
                }

                if let result = bridge.moduleProbeResult[probe] {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Responder", value: result.responder)
                        LabeledContent("Data identifier", value: result.did)
                        LabeledContent("Data bytes", value: result.byteCount.formatted())
                        if let transmission = result.transmission {
                            LabeledContent("Distinction code", value: transmission.distinctionCode)
                            LabeledContent("Data list 2201", value: transmission.dataStatus)
                        }
                        rawResponse("Raw response", hex: result.rawHex)
                        if let rawHex = result.transmission?.rawHex {
                            rawResponse("Data list 2201 raw response", hex: rawHex)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("module-scan-result")
                }

                if let report = bridge.moduleProbeReport[probe] {
                    ShareLink(item: report, subject: Text("Honda/Acura module scan report")) {
                        Label("Share Module Scan", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("share-module-scan")
                }
            }
        }
    }

    private func rawResponse(_ title: String, hex: String) -> some View {
        DisclosureGroup(title) {
            Text(verbatim: hex)
                .font(.caption.monospaced())
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private var engineReadings: some View {
        section("Standard OBD-II readings") {
            VStack(alignment: .leading, spacing: 12) {
                let metrics = DemoMetric.allCases.filter { !vehicle.readings(for: $0).isEmpty }
                if metrics.isEmpty {
                    Text("Connect to FIXD and start monitoring to see supported readings.")
                        .font(.subheadline)
                        .foregroundStyle(GarageTheme.mutedText)
                }

                ForEach(metrics) { metric in
                    if metric != metrics.first { Divider() }
                    ForEach(vehicle.readings(for: metric)) { reading in
                        LabeledContent {
                            Text("\(metric.display(reading.value)) \(metric.unit)")
                                .monospacedDigit()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(metric.title)
                                ecuLabel(reading.ecu)
                            }
                        }
                    }
                }
            }
        }
    }

    private var engineTroubleCodes: some View {
        section("Standard OBD-II trouble codes") {
            VStack(alignment: .leading, spacing: 12) {
                let groups = vehicle.troubleCodes
                if groups.isEmpty {
                    Text("Run a vehicle scan to check for trouble codes.")
                        .font(.subheadline)
                        .foregroundStyle(GarageTheme.mutedText)
                }

                ForEach(groups) { group in
                    if group.id != groups.first?.id { Divider() }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                        if let status = group.status {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(GarageTheme.mutedText)
                        }
                        ForEach(group.ecus) { ecu in
                            VStack(alignment: .leading, spacing: 4) {
                                ecuLabel(ecu.id)
                                if let unavailable = ecu.unavailableReason {
                                    Text(unavailable)
                                        .foregroundStyle(GarageTheme.mutedText)
                                } else if ecu.codes.isEmpty {
                                    Text("No codes returned")
                                        .foregroundStyle(GarageTheme.mutedText)
                                } else {
                                    VehicleTroubleCodeList(codes: ecu.codes)
                                }
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func ecuLabel(_ identifier: String) -> some View {
        Text("ECU " + identifier)
            .font(.caption.monospaced())
            .foregroundStyle(GarageTheme.mutedText)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            GaragePanel(content: content)
        }
    }

    private func items(_ title: String, values: [String], status: String) -> some View {
        section(title) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(values, id: \.self) { value in
                    if value != values.first {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value)
                            .font(.subheadline.weight(.semibold))
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(GarageTheme.mutedText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
