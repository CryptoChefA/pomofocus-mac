import AppKit
import SwiftUI

/// Restyles the whole app with a soft crossfade, without asking every view to animate
/// every colour, shadow and gradient for half a second. A picture of the window as it
/// looks now goes on top, the new look is laid out underneath in a single pass, and the
/// picture fades away. One layer's opacity is all that moves.
@MainActor
enum ThemeCrossfade {
    static let duration: TimeInterval = 0.45

    static func perform(reduceMotion: Bool, _ change: () -> Void) {
        guard !reduceMotion,
              let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let content = window.contentView,
              let picture = snapshot(of: window, content: content)
        else {
            change()
            return
        }

        let cover = Cover(frame: content.bounds)
        cover.autoresizingMask = [.width, .height]
        cover.wantsLayer = true
        cover.layer?.contents = picture
        cover.layer?.contentsGravity = .resize
        content.addSubview(cover, positioned: .above, relativeTo: nil)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cover.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { cover.removeFromSuperview() }
        })
    }

    /// Everything the window is showing, as the window server composed it, so moving
    /// scenery and flattened layers are in the picture too. Falls back to drawing the
    /// view tree if the window server's copy isn't available.
    private static func snapshot(of window: NSWindow, content: NSView) -> CGImage? {
        let frame = window.frame
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let bounds = CGRect(x: frame.minX, y: screenHeight - frame.maxY, width: frame.width, height: frame.height)
        if let image = CGWindowListCreateImage(bounds, .optionIncludingWindow, CGWindowID(window.windowNumber), [.bestResolution]),
           image.width > 1 {
            return image
        }
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        return bitmap.cgImage
    }

    /// The picture of the old look. Clicks go straight through it.
    private final class Cover: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isOpaque: Bool { false }
    }
}
