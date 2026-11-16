import AppKit
import SwiftUI

/// What the menu bar item is showing right now.
enum MenuBarState: Equatable {
    case needsPermission
    case idle
    case typing(wpm: Int)
}

/// Draws the whole menu bar label (gauge glyph + optional number) into one
/// *template* NSImage. One image instead of a SwiftUI Image/Text mix because:
/// - it can never come out empty (a missing SF Symbol falls back to a drawn gauge),
/// - template images are tinted by the system for light/dark/tinted menu bars,
/// - the number gets a fixed width, so the item doesn't jiggle as digits change.
enum MenuBarIcon {
    static let symbolName = "gauge.with.dots.needle.67percent"
    static let height: CGFloat = 18

    static func image(state: MenuBarState, style: MenuBarStyle) -> NSImage {
        let glyph = symbol()
        let glyphAlpha: CGFloat = state == .idle ? 0.55 : 1

        var text: NSAttributedString?
        var textWidth: CGFloat = 0
        if case .typing(let wpm) = state, style != .iconOnly {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let s = style == .iconNumberUnit ? "\(wpm) wpm" : "\(wpm)"
            text = NSAttributedString(string: s, attributes: attrs)
            // Reserve room for three digits so the item width stays put.
            let reserve = NSAttributedString(string: style == .iconNumberUnit ? "000 wpm" : "000", attributes: attrs)
            textWidth = ceil(max(reserve.size().width, text!.size().width))
        }

        let gap: CGFloat = text == nil ? 0 : 4
        let size = NSSize(width: ceil(glyph.size.width) + gap + textWidth, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let gRect = NSRect(x: 0, y: (rect.height - glyph.size.height) / 2,
                               width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: gRect, from: .zero, operation: .sourceOver, fraction: glyphAlpha)

            if state == .needsPermission {
                // Knock a ring out of the glyph's top-right corner, then draw a badge dot in it.
                let r: CGFloat = 3.6
                let c = NSPoint(x: gRect.maxX - r + 0.5, y: gRect.maxY - r + 0.5)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: c.x - r - 1.6, y: c.y - r - 1.6, width: 2 * (r + 1.6), height: 2 * (r + 1.6))).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
            }

            if let text {
                let h = text.size().height
                text.draw(at: NSPoint(x: gRect.maxX + gap, y: (rect.height - h) / 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = switch state {
        case .needsPermission: "WPM: needs Input Monitoring permission"
        case .idle: "WPM: idle"
        case .typing(let wpm): "WPM: \(wpm) words per minute"
        }
        return image
    }

    /// The SF Symbol, or a drawn gauge if the symbol is ever unavailable.
    private static func symbol() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WPM")?
            .withSymbolConfiguration(config) {
            return img
        }
        return NSImage(size: NSSize(width: 17, height: 15), flipped: false) { r in
            let c = NSPoint(x: r.midX, y: 4)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: c, radius: 7, startAngle: 0, endAngle: 180)
            arc.lineWidth = 1.8
            arc.lineCapStyle = .round
            NSColor.black.setStroke()
            arc.stroke()
            let needle = NSBezierPath()
            needle.move(to: c)
            needle.line(to: NSPoint(x: c.x + 4, y: c.y + 4.5))
            needle.lineWidth = 1.8
            needle.lineCapStyle = .round
            needle.stroke()
            return true
        }
    }
}

struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        MenuBarStateLabel(state: model.menuBarState, style: model.menuBarStyle)
    }
}

struct MenuBarStateLabel: View {
    let state: MenuBarState
    let style: MenuBarStyle

    var body: some View {
        Image(nsImage: MenuBarIcon.image(state: state, style: style))
            .renderingMode(.template)
    }
}
