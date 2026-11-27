import SwiftUI

struct DiagnosticsView: View {
    var body: some View {
        GarageScreen {
            GaragePanel {
                NavigationLink {
                    AdapterInspectorView()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title3)
                            .foregroundStyle(GarageTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Inspect a Bluetooth adapter")
                                .font(.headline)
                            Text("Discover nearby devices and inspect their services and characteristics.")
                                .font(.subheadline)
                                .foregroundStyle(GarageTheme.mutedText)
                            }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GarageTheme.mutedText)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            GaragePanel {
                NavigationLink {
                    ServiceFunctionsView()
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.title3)
                            .foregroundStyle(GarageTheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Honda/Acura service functions")
                                .font(.headline)
                            Text("Review PCM reset, idle learn, and verification requirements.")
                                .font(.subheadline)
                                .foregroundStyle(GarageTheme.mutedText)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(GarageTheme.mutedText)
                            .padding(.top, 3)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("2011 Acura MDX")
                    .font(.title2.bold())
                Text("Advanced diagnostics require commands and responses verified on this vehicle.")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
                GaragePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        capability("Individual cylinder misfires", icon: "exclamationmark.circle")
                        Divider()
                        capability("Transmission and torque converter", icon: "gearshape.2")
                        Divider()
                        capability("Knock correction", icon: "bolt")
                        Divider()
                        capability("Enhanced fuel trims", icon: "fuelpump")
                        Divider()
                        capability("Other manufacturer-specific PIDs", icon: "list.bullet.rectangle")
                    }
                }
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func capability(_ title: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(GarageTheme.mutedText)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("Unavailable")
                    .font(.caption)
                    .foregroundStyle(GarageTheme.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
