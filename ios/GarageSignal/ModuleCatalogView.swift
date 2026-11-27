import SwiftUI

private struct VehicleModule: Identifiable {
    let id: String
    let name: String
    let icon: String
    let detail: String
    let readings: [String]
    let serviceFunctions: [String]

    static let powertrain: [VehicleModule] = [
        .init(
            id: "pcm", name: "Engine and PCM", icon: "engine.combustion",
            detail: "3.7 L V6 · PGM-FI powertrain control",
            readings: [
                "PCM identification and calibration", "Engine RPM, load and coolant temperature",
                "Bank 1 and Bank 2 fuel trims", "Ignition advance and knock correction",
                "Cylinder 1–6 misfire counts", "DTCs, freeze frame and monitor readiness"
            ],
            serviceFunctions: ["PCM learned-value reset", "Throttle position learn", "Idle learn"]
        ),
        .init(
            id: "transmission", name: "Automatic transmission", icon: "gearshape.2",
            detail: "Six-speed automatic · torque converter and lock-up clutch",
            readings: [
                "ATF temperature", "Current and commanded gear", "Mainshaft and countershaft RPM",
                "Torque converter clutch state", "Torque converter slip",
                "Transmission diagnostics and calibration identification"
            ],
            serviceFunctions: ["Transmission adaptation or relearn, where supported"]
        ),
        .init(
            id: "shawd", name: "SH-AWD", icon: "car.side",
            detail: "Super Handling All-Wheel Drive · rear torque distribution",
            readings: [
                "SH-AWD DTCs", "Rear differential temperature, if exposed",
                "Left and right rear clutch command or current, if exposed",
                "Torque distribution data, if exposed"
            ],
            serviceFunctions: ["OEM SH-AWD function tests, where supported"]
        ),
    ]

    static let otherSystems: [VehicleModule] = [
        .init(
            id: "vsa", name: "ABS and VSA", icon: "steeringwheel",
            detail: "Braking and vehicle stability",
            readings: ["Chassis DTCs", "Four wheel speeds", "Steering angle and yaw data, if exposed"],
            serviceFunctions: ["VSA sensor calibration, where supported"]
        ),
        .init(
            id: "srs", name: "SRS", icon: "person.crop.circle",
            detail: "Airbag and supplemental restraint diagnostics",
            readings: ["SRS DTCs", "Control unit identification, if exposed"], serviceFunctions: []
        ),
        .init(
            id: "tpms", name: "TPMS", icon: "exclamationmark.circle",
            detail: "Tire pressure monitoring",
            readings: ["TPMS DTCs", "Per-wheel pressure and sensor state, if exposed"],
            serviceFunctions: ["Sensor registration, where supported"]
        ),
        .init(
            id: "body", name: "Body and multiplex", icon: "car.rear",
            detail: "Body control, cluster and trim-dependent modules",
            readings: [
                "Body DTCs", "Battery voltage and body switch states, if exposed",
                "Instrument cluster identification, if exposed", "Parking assistance status, if equipped"
            ],
            serviceFunctions: []
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
    var body: some View {
        GarageScreen {
            VStack(alignment: .leading, spacing: 6) {
                Text("2011 Acura MDX 3.7L SH-AWD")
                    .font(.title2.bold())
                Text("Module inventory and readings need verification on your vehicle. This list describes the systems in scope.")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
            }
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
                            ModuleDetailsView(module: module)
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
                    }
                }
            }
        }
    }
}

private struct ModuleDetailsView: View {
    let module: VehicleModule

    var body: some View {
        GarageScreen {
            VStack(alignment: .leading, spacing: 8) {
                Text(module.detail)
                    .font(.title3.bold())
                Text("Vehicle support unverified")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GarageTheme.warning)
            }
            items("Read-only diagnostics", values: module.readings, status: "Awaiting vehicle validation")
            if !module.serviceFunctions.isEmpty {
                items("Service functions", values: module.serviceFunctions, status: "Unavailable")
            }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func items(_ title: String, values: [String], status: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            GaragePanel {
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
}
