import SwiftUI

struct ServiceFunctionsView: View {
    var body: some View {
        GarageScreen {
            VStack(alignment: .leading, spacing: 5) {
                Text("2011 Acura MDX")
                    .font(.title2.bold())
                Text("3.7L · SH-AWD · Honda/Acura")
                    .font(.subheadline)
                    .foregroundStyle(GarageTheme.mutedText)
            }

            GaragePanel {
                VStack(alignment: .leading, spacing: 12) {
                    service(
                        "PCM learned-value reset",
                        detail: "Verify what the matched PCM procedure clears and which relearns must follow."
                    )
                    Divider()
                    service(
                        "PCM idle learn",
                        detail: "Verify the OEM relearn procedure and the required operating conditions."
                    )
                    Divider()
                    service(
                        "Throttle position learn",
                        detail: "Verify the Honda/Acura electronic throttle procedure for the repair and PCM."
                    )
                    Divider()
                    service(
                        "Transmission adaptation service",
                        detail: "Verify available functions for the transmission and controller fitted to this vehicle."
                    )
                    Divider()
                    service(
                        "VSA sensor calibration",
                        detail: "Verify the chassis controller and the conditions for neutral-position calibration."
                    )
                }
            }

            GaragePanel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Required verification", systemImage: "checkmark.shield")
                        .font(.headline)
                        .foregroundStyle(GarageTheme.accent)
                    Text("Match the vehicle and ECU to the Honda/Acura service procedure. Confirm adapter support and verify required voltage, ignition and engine conditions. Save current codes and freeze-frame data before any reset.")
                        .font(.subheadline)
                        .foregroundStyle(GarageTheme.mutedText)
                }
            }
        }
        .navigationTitle("Service Functions")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func service(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(GarageTheme.mutedText)
            Text("Unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(GarageTheme.warning)
        }
        .accessibilityElement(children: .combine)
    }
}
