import AppKit
import ObjectiveC

/// Slim scroll bars everywhere in the app: a thin rounded knob with no track, which stays
/// thin when the pointer is over it. macOS still fades it in while scrolling and out after.
enum ThinScrollBars {
    @MainActor private static var installed = false

    /// Gives every scroll view the slim scroller as it joins a window. Runs once at launch.
    @MainActor
    static func apply() {
        guard !installed else { return }
        installed = true
        let cls: AnyClass = NSScrollView.self
        let selector = #selector(NSView.viewDidMoveToWindow)
        guard let method = class_getInstanceMethod(cls, selector) else { return }
        let original = method_getImplementation(method)
        typealias Original = @convention(c) (AnyObject, Selector) -> Void
        let block: @convention(block) (NSScrollView) -> Void = { scrollView in
            unsafeBitCast(original, to: Original.self)(scrollView, selector)
            scrollView.useThinScrollers()
        }
        let replacement = imp_implementationWithBlock(block)
        // Add the override on NSScrollView itself, so NSView's version is never touched.
        if !class_addMethod(cls, selector, replacement, method_getTypeEncoding(method)) {
            method_setImplementation(method, replacement)
        }
    }
}

private extension NSScrollView {
    func useThinScrollers() {
        guard window != nil else { return }
        if hasVerticalScroller, !(verticalScroller is ThinScroller) {
            verticalScroller = ThinScroller()
        }
        if hasHorizontalScroller, !(horizontalScroller is ThinScroller) {
            horizontalScroller = ThinScroller()
        }
    }
}

/// A 4-point knob in the theme's secondary ink, no slot behind it.
final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        let thickness: CGFloat = 4
        let inset: CGFloat = 3
        let vertical = bounds.height >= bounds.width
        let drawn = vertical
            ? NSRect(x: bounds.maxX - thickness - inset, y: knob.minY + 2, width: thickness, height: max(knob.height - 4, thickness))
            : NSRect(x: knob.minX + 2, y: bounds.maxY - thickness - inset, width: max(knob.width - 4, thickness), height: thickness)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: drawn, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}
