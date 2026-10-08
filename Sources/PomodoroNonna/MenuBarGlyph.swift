import AppKit

/// Draws the menu-bar item as a cockpit "focus tank": a dark lens chip whose fill drains
/// as the session runs, with the time inside. The digits flip dark where the fill sits
/// under them, so they stay readable. White while focusing, green on a break, red (blinking)
/// in overtime, dim while paused. During the opening breath ritual the tank breathes with
/// you: it fills as you inhale and empties as you exhale.
enum MenuBarGlyph {
    enum Tone {
        case focus, rest, alert, paused, idle

        var color: NSColor {
            switch self {
            case .focus: return NSColor(white: 0.9, alpha: 1)
            case .rest: return NSColor(srgbRed: 0.275, green: 1.0, blue: 0.478, alpha: 1)
            case .alert: return NSColor(srgbRed: 1.0, green: 0.2, blue: 0.16, alpha: 1)
            case .paused: return NSColor(white: 0.55, alpha: 1)
            case .idle: return NSColor(white: 0.42, alpha: 1)
            }
        }
    }

    private static let lens = NSColor(srgbRed: 0.055, green: 0.063, blue: 0.059, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.09, green: 0.05, blue: 0.02, alpha: 1)

    /// - Parameters:
    ///   - text: the legend, e.g. "24:13", "BREATHE", "DONE". `nil` draws the idle chip.
    ///   - fill: 0...1 of the tank that is still full (time left, or the breath).
    ///   - tone: which colour the chip takes.
    ///   - lit: blink phase; `false` dims the chip (used for overtime).
    /// The last chip drawn. The label is asked for an image on every clock tick and
    /// every pulse, but most of those produce the same picture.
    @MainActor private static var lastImage: (key: String, image: NSImage)?

    @MainActor
    static func image(text: String?, fill: Double, tone: Tone, isPaused: Bool = false, lit: Bool = true) -> NSImage {
        // Fill is quantised to 1/400 — finer than one pixel of the widest chip.
        let key = "\(text ?? "-")|\(Int((fill.isFinite ? fill : 0) * 400))|\(tone)|\(isPaused)|\(lit)"
        if let lastImage, lastImage.key == key { return lastImage.image }
        let image = render(text: text, fill: fill, tone: tone, isPaused: isPaused, lit: lit)
        lastImage = (key, image)
        return image
    }

    private static func render(text: String?, fill: Double, tone: Tone, isPaused: Bool, lit: Bool) -> NSImage {
        let height: CGFloat = 18
        let chipHeight: CGFloat = 16
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        let label = text?.uppercased()
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.6]
        let textWidth = label.map { ceil(NSAttributedString(string: $0, attributes: attrs).size().width) } ?? 0
        let width = label == nil ? 26 : max(46, textWidth + 18)
        let alpha: CGFloat = lit ? 1 : 0.28
        let color = tone.color.withAlphaComponent(alpha)
        let clamped = CGFloat(min(1, max(0, fill.isFinite ? fill : 0)))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let chip = NSRect(x: 0.5, y: (height - chipHeight) / 2 + 0.5, width: width - 1, height: chipHeight - 1)
            let body = NSBezierPath(roundedRect: chip, xRadius: 3.5, yRadius: 3.5)
            lens.setFill()
            body.fill()
            color.withAlphaComponent(alpha * 0.5).setStroke()
            body.lineWidth = 1
            body.stroke()

            guard let label else {
                // Idle: an empty tank. It needs a visible rim, or the chip disappears
                // into a dark menu bar and just looks like a gap.
                NSColor(white: 0.62, alpha: 1).setStroke()
                body.lineWidth = 1
                body.stroke()
                let pin = NSBezierPath(ovalIn: NSRect(x: chip.midX - 1.6, y: chip.midY - 1.6, width: 3.2, height: 3.2))
                NSColor(white: 0.78, alpha: 1).setFill()
                pin.fill()
                return true
            }

            let inner = chip.insetBy(dx: 2, dy: 2)
            let fillRect = NSRect(x: inner.minX, y: inner.minY, width: max(clamped > 0 ? 1.2 : 0, inner.width * clamped),
                                  height: inner.height)
            color.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()

            // Legend twice: in the chip's colour, then in ink wherever the fill is under it
            func drawLabel(_ c: NSColor) {
                let str = NSAttributedString(string: label, attributes: [
                    .font: font, .foregroundColor: c, .kern: 0.6])
                let size = str.size()
                str.draw(at: NSPoint(x: chip.midX - (size.width - 0.6) / 2, y: chip.midY - size.height / 2))
            }
            drawLabel(color)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: fillRect).addClip()
            drawLabel(ink.withAlphaComponent(alpha))
            NSGraphicsContext.restoreGraphicsState()

            if isPaused {
                // Two bars at the right edge, like a pause key
                color.setFill()
                for offset in [CGFloat(-4.6), CGFloat(-2.0)] {
                    NSBezierPath(rect: NSRect(x: chip.maxX + offset, y: chip.midY - 2.4, width: 1.2, height: 4.8)).fill()
                }
            }
            return true
        }
        image.isTemplate = false      // the chip has its own dark lens, like the Annunciator lights
        return image
    }
}
