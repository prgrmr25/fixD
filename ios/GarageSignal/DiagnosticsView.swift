import SwiftUI

struct DiagnosticsView: View {
    var body: some View {
        GarageScreen {
            diagnosticLink(
                "Inspect a Bluetooth adapter",
                detail: "Discover a nearby adapter and inspect its services and characteristics.",
                icon: "antenna.radiowaves.left.and.right"
            ) {
                AdapterInspectorView()
            }
            diagnosticLink(
                "2011 Acura MDX modules",
                detail: "Explore PCM, transmission, SH-AWD and other vehicle systems.",
                icon: "car.side"
            ) {
                ModuleCatalogView()
            }
            diagnosticLink(
                "Honda/Acura service functions",
                detail: "Review PCM reset, idle learn, and verification requirements.",
                icon: "wrench.and.screwdriver"
            ) {
                ServiceFunctionsView()
            }
        }
        .navigationTitle("Diagnostics")
    }

    private func diagnosticLink<Destination: View>(
        _ title: String,
        detail: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        GaragePanel {
            NavigationLink {
                destination()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(GarageTheme.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(GarageTheme.mutedText)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(GarageTheme.mutedText)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
