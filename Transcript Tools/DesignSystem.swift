import SwiftUI

enum BrandTheme {
    static let primaryAccent = Color(red: 0.42, green: 0.42, blue: 0.42)
    static let secondaryAccent = Color(red: 0.62, green: 0.62, blue: 0.62)
    static let contentBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let sidebarBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let softSurface = Color(nsColor: NSColor.controlBackgroundColor)
    static let border = Color.primary.opacity(0.10)
    static let mutedBorder = Color.primary.opacity(0.06)
    static let mutedText = Color.secondary
}

struct AppPanelModifier: ViewModifier {
    let padding: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        if #available(macOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular, in: shape)
                .overlay {
                    shape.stroke(BrandTheme.border, lineWidth: 1)
                }
        } else {
            content
                .padding(padding)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(BrandTheme.border, lineWidth: 1)
                }
        }
    }
}

struct GlassProminentControlModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

struct GlassControlModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct GlassCapsuleModifier: ViewModifier {
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint.opacity(0.18)), in: Capsule())
        } else {
            content
                .background(tint.opacity(0.12), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(tint.opacity(0.24), lineWidth: 1)
                }
        }
    }
}

extension View {
    func appPanel(padding: CGFloat = 14) -> some View {
        modifier(AppPanelModifier(padding: padding))
    }

    func glassControl() -> some View {
        modifier(GlassControlModifier())
    }

    func glassProminentControl() -> some View {
        modifier(GlassProminentControlModifier())
    }

    func glassCapsule(tint: Color) -> some View {
        modifier(GlassCapsuleModifier(tint: tint))
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: systemImage)
                .imageScale(.small)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(tint: tint)
    }
}
