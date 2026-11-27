import SwiftUI

enum GarageTheme {
    static let backdrop = Color(red: 0.067, green: 0.086, blue: 0.102)
    static let surface = Color(red: 0.102, green: 0.125, blue: 0.143)
    static let stroke = Color(white: 1, opacity: 0.095)
    static let accent = Color(red: 0.427, green: 0.933, blue: 0.765)
    static let mutedText = Color(red: 0.642, green: 0.700, blue: 0.710)
    static let warning = Color(red: 1.0, green: 0.690, blue: 0.475)
}

struct GaragePanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(GarageTheme.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(GarageTheme.stroke)
                    .allowsHitTesting(false)
            }
    }
}

struct GarageScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .frame(maxWidth: 920)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .background(GarageTheme.backdrop)
    }
}

struct SourceLabel: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "waveform")
            .font(.caption.weight(.semibold))
            .foregroundStyle(GarageTheme.accent)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(GarageTheme.accent.opacity(0.10), in: Capsule())
    }
}
