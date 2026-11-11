import AppKit
import QuartzCore
import SwiftUI

/// The big clock on the Focus screen, with digits that roll as they change.
///
/// The roll is the same as `RollingClockText`'s (a changed digit slides out and fades as
/// the new one slides in, 0.24 s, ease in and out), but it's done with Core Animation, so
/// the motion runs in the system compositor. A SwiftUI animation makes the app lay out
/// and redraw the window on every frame; the roll every second cost about 7% CPU while
/// the window was in view. This way the app does nothing between the second's changes.
struct LayerRollingClock: NSViewRepresentable {
    let text: String
    let countsDown: Bool
    let travel: CGFloat
    /// False with Reduce Motion: the digits change in place.
    let animated: Bool
    let size: CGFloat
    var weight: NSFont.Weight = .medium
    /// Matches SwiftUI's `.tracking`.
    var tracking: CGFloat = -2
    var duration: Double = 0.24
    let color: Color
    /// The overtime glow, and its slow flash.
    var glows = false
    var glowOpacity: Double = 0.45
    var glowRadius: CGFloat = 14
    var flashes = false

    func makeNSView(context: Context) -> RollingDigitsView {
        RollingDigitsView()
    }

    func updateNSView(_ view: RollingDigitsView, context: Context) {
        view.configure(
            font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight), tracking: tracking,
            duration: duration, color: NSColor(color), travel: travel,
            glow: glows ? (glowOpacity, glowRadius) : nil, flashes: flashes
        )
        view.show(text, countsDown: countsDown, animated: animated)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RollingDigitsView, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }
}

/// One text layer per character, keyed from the right so "9:59" → "10:00" keeps the
/// seconds in place.
final class RollingDigitsView: NSView {
    private var font = NSFont.monospacedDigitSystemFont(ofSize: 56, weight: .medium)
    private var color = NSColor.white
    private var travel: CGFloat = 22
    private var glow: (opacity: Double, radius: CGFloat)?
    private var flashes = false
    private var kern: CGFloat = -2
    private var duration: CFTimeInterval = 0.24
    private static let flashPeriod = 1.35

    private var text = ""
    /// Index 0 is the rightmost character.
    private var slots: [CATextLayer] = []
    private let digits = CALayer()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        digits.masksToBounds = false
        layer?.addSublayer(digits)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize {
        let widths = text.map(width(of:))
        return NSSize(width: ceil(widths.reduce(0, +)), height: lineHeight)
    }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    private func width(of character: Character) -> CGFloat {
        NSAttributedString(string: String(character), attributes: [.font: font]).size().width + kern
    }

    func configure(font newFont: NSFont, tracking: CGFloat, duration: Double, color: NSColor, travel: CGFloat,
                   glow: (opacity: Double, radius: CGFloat)?, flashes: Bool) {
        let fontChanged = newFont != font || tracking != kern
        let colorChanged = color != self.color
        font = newFont
        kern = tracking
        self.duration = duration
        self.color = color
        self.travel = travel
        if fontChanged || colorChanged {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in slots { style(layer, character: layer.name ?? "") }
            // Widths may have changed with the font, so put each character back in place.
            let positions = xPositions(for: Array(text))
            for (slot, layer) in slots.enumerated() where slot < text.count {
                let index = text.count - 1 - slot
                layer.frame = frame(for: Array(text)[index], x: positions[index])
            }
            CATransaction.commit()
            if fontChanged { invalidateIntrinsicContentSize() }
        }
        let glowChanged = glow?.opacity != self.glow?.opacity || glow?.radius != self.glow?.radius
        if glowChanged || flashes != self.flashes || colorChanged {
            self.glow = glow
            self.flashes = flashes
            updateGlowAndFlash()
        }
    }

    func show(_ newText: String, countsDown: Bool, animated: Bool) {
        guard newText != text else { return }
        let old = Array(text), new = Array(newText)
        let lengthChanged = old.count != new.count
        text = newText
        if lengthChanged { invalidateIntrinsicContentSize() }

        let positions = xPositions(for: new)
        let direction: CGFloat = countsDown ? 1 : -1
        let animate = animated && window != nil && !old.isEmpty
        var kept: [CATextLayer] = []
        var leaving: [CALayer] = []

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Set before the animations are added: it then runs once they've finished, taking
        // away the digits that rolled out.
        CATransaction.setCompletionBlock { leaving.forEach { $0.removeFromSuperlayer() } }
        for slot in 0..<max(old.count, new.count) {
            let newCharacter: Character? = slot < new.count ? new[new.count - 1 - slot] : nil
            let oldCharacter: Character? = slot < old.count ? old[old.count - 1 - slot] : nil
            let existing = slot < slots.count ? slots[slot] : nil

            if let newCharacter, newCharacter == oldCharacter, let existing {
                existing.frame = frame(for: newCharacter, x: positions[new.count - 1 - slot])
                kept.append(existing)
                continue
            }
            if let existing {
                if animate {
                    roll(existing, out: true, by: travel * direction)
                    leaving.append(existing)
                } else {
                    existing.removeFromSuperlayer()
                }
            }
            if let newCharacter {
                let layer = CATextLayer()
                style(layer, character: String(newCharacter))
                layer.frame = frame(for: newCharacter, x: positions[new.count - 1 - slot])
                digits.addSublayer(layer)
                if animate { roll(layer, out: false, by: travel * direction) }
                kept.append(layer)
            }
        }
        CATransaction.commit()
        slots = kept
    }

    private func xPositions(for characters: [Character]) -> [CGFloat] {
        var x: CGFloat = 0
        return characters.map { character in
            defer { x += width(of: character) }
            return x
        }
    }

    private func frame(for character: Character, x: CGFloat) -> CGRect {
        if character == ":" {
            // Drawn as "0:0" with clear zeros (see `style`), so it starts a digit earlier.
            let zero = width(of: "0")
            return CGRect(x: x - zero, y: 0, width: zero * 2 + width(of: ":"), height: lineHeight)
        }
        return CGRect(x: x, y: 0, width: width(of: character) - kern, height: lineHeight)
    }

    private func style(_ layer: CATextLayer, character: String) {
        layer.name = character
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: resolved(color), .kern: kern]
        if character == ":" {
            // San Francisco raises a colon that sits between digits to the middle of them,
            // as SwiftUI's whole-string text does. Alone it would sit low, so it's drawn with
            // invisible digits either side.
            let clear: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.clear.cgColor, .kern: kern]
            let string = NSMutableAttributedString(string: "0", attributes: clear)
            string.append(NSAttributedString(string: ":", attributes: attributes))
            string.append(NSAttributedString(string: "0", attributes: clear))
            layer.string = string
        } else {
            layer.string = NSAttributedString(string: character, attributes: attributes)
        }
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.alignmentMode = .left
        layer.truncationMode = .none
        layer.isWrapped = false
        layer.allowsFontSubpixelQuantization = true
    }

    /// Slides a digit in (from `distance` above, for a countdown) or out (to `distance`
    /// below), fading as it goes.
    private func roll(_ layer: CATextLayer, out: Bool, by distance: CGFloat) {
        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let move = CABasicAnimation(keyPath: "transform.translation.y")
        move.fromValue = out ? 0 : -distance
        move.toValue = out ? distance : 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = out ? 1 : 0
        fade.toValue = out ? 0 : 1
        let group = CAAnimationGroup()
        group.animations = [move, fade]
        group.duration = duration
        group.timingFunction = ease
        if out {
            layer.opacity = 0
            layer.setValue(distance, forKeyPath: "transform.translation.y")
        }
        layer.add(group, forKey: "roll")
    }

    private func updateGlowAndFlash() {
        digits.shadowColor = glow.flatMap { resolved(NSColor(NonnaTheme.alert)).copy(alpha: $0.opacity) }
        digits.shadowOpacity = glow == nil ? 0 : 1
        digits.shadowRadius = glow?.radius ?? 0
        digits.shadowOffset = .zero

        digits.removeAnimation(forKey: "flash")
        guard flashes, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // The same beat as `alertFlash`: lit and dim for 1.35 s each, easing between them
        // over 0.72 s, in step with the other flashing parts of the screen.
        let period = Self.flashPeriod, cycle = period * 2, ease = 0.72
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [1, 0.62, 0.62, 1, 1]
        flash.keyTimes = [0, ease / cycle, period / cycle, (period + ease) / cycle, 1].map { NSNumber(value: $0) }
        let inOut = CAMediaTimingFunction(name: .easeInEaseOut), linear = CAMediaTimingFunction(name: .linear)
        flash.timingFunctions = [inOut, linear, inOut, linear]
        flash.duration = cycle
        flash.repeatCount = .infinity
        // Dimming starts when the reference-date clock crosses an odd multiple of the period.
        let now = Date().timeIntervalSinceReferenceDate
        flash.timeOffset = (now - period).truncatingRemainder(dividingBy: cycle)
        digits.add(flash, forKey: "flash")
    }

    private func resolved(_ color: NSColor) -> CGColor {
        var result = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { result = color.cgColor }
        return result
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        digits.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in slots { layer.contentsScale = scale }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeBackingProperties()
        if flashes { updateGlowAndFlash() }
    }
}
