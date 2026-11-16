import SwiftUI

/// Calm, minimal palette. Everything else comes from system semantic colors,
/// so light/dark switching is automatic.
enum Palette {
    /// Soft amber accent used for the live number and chart.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.95, green: 0.72, blue: 0.36, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.50, blue: 0.13, alpha: 1)
    })
}

extension Font {
    /// Monospaced digits in a light weight, for the hero number.
    static func hero(_ size: CGFloat) -> Font { .system(size: size, weight: .light, design: .monospaced) }
    static let statValue = Font.system(size: 17, weight: .regular, design: .monospaced)
    static let statLabel = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}

/// Rounded "tile" background: Liquid Glass on macOS 26+, a quiet fill on macOS 15.
struct TileBackground: ViewModifier {
    var cornerRadius: CGFloat = 12
    @Environment(\.offscreenRender) private var offscreen
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !offscreen {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Groups glass tiles so they blend/morph together on macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    @Environment(\.offscreenRender) private var offscreen
    var body: some View {
        if #available(macOS 26, *), !offscreen {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Small icon/text buttons: glass on macOS 26, borderless on macOS 15.
struct QuietButtonStyle: ViewModifier {
    var prominent = false
    @Environment(\.offscreenRender) private var offscreen
    func body(content: Content) -> some View {
        if #available(macOS 26, *), !offscreen {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            if prominent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        }
    }
}

extension View {
    func tile(cornerRadius: CGFloat = 12) -> some View { modifier(TileBackground(cornerRadius: cornerRadius)) }
    func quietButton(prominent: Bool = false) -> some View { modifier(QuietButtonStyle(prominent: prominent)) }
}

extension EnvironmentValues {
    /// True when rendering with ImageRenderer, which can't draw Liquid Glass.
    var offscreenRender: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}

private struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}
