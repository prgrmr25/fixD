import SwiftUI

enum DiagnosticRoute: Hashable {
    case adapter
    case modules
    case serviceFunctions
}

struct DiagnosticsView: View {
    var body: some View {
        GarageScreen {
            diagnosticLink(
                "Scan a vehicle with FIXD",
                detail: "Connect to your FIXD for live standard readings and trouble codes.",
                icon: "antenna.radiowaves.left.and.right",
                route: .adapter
            )
            diagnosticLink(
                "2011 Acura MDX modules",
                detail: "Explore PCM, transmission, SH-AWD and other vehicle systems.",
                icon: "car.side",
                route: .modules
            )
            diagnosticLink(
                "Honda/Acura service functions",
                detail: "Review PCM reset, idle learn, and verification requirements.",
                icon: "wrench.and.screwdriver",
                route: .serviceFunctions
            )
        }
        .navigationTitle("Diagnostics")
    }

    private func diagnosticLink(
        _ title: String,
        detail: String,
        icon: String,
        route: DiagnosticRoute
    ) -> some View {
        GaragePanel {
            NavigationLink(value: route) {
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
            .accessibilityIdentifier(title)
        }
    }
}
