import AppKit
import SwiftUI

/// The silent alert: when a block or break ends, a soft glow breathes in around the edges of
/// every screen, three times, then fades. It's for a library with the sound off, or a
/// full-screen app that hides the menu bar: a borderless panel on each screen that floats
/// over everything, full-screen spaces included, and never takes a click or the focus.
@MainActor
final class ScreenGlow {
    static let shared = ScreenGlow()

    private var panels: [NSPanel] = []
    private var hideTask: Task<Void, Never>?
    /// How long the glow stays: three slow breaths.
    private static let duration: Duration = .seconds(7)

    /// - Parameter color: the glow's colour; nil uses the theme's accent.
    func show(color: NSColor?) {
        dismiss()
        let tint = color.map { Color(nsColor: $0) } ?? NonnaTheme.terracotta
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: GlowEdges(color: tint, reduceMotion: reduceMotion))
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        let closing = panels
        panels = []
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            closing.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            MainActor.assumeIsolated { closing.forEach { $0.orderOut(nil) } }
        }
    }

    func dismiss() {
        hideTask?.cancel()
        hideTask = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
    }
}

/// A glow that comes in from the screen's edges and leaves the middle clear.
private struct GlowEdges: View {
    let color: Color
    let reduceMotion: Bool
    @State private var lit = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Rectangle()
                    .strokeBorder(color, lineWidth: 26)
                    .blur(radius: 30)
                Rectangle()
                    .strokeBorder(color.opacity(0.85), lineWidth: 4)
                    .blur(radius: 6)
            }
            .frame(width: size.width, height: size.height)
            .opacity(lit ? 0.95 : (reduceMotion ? 0.7 : 0.15))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeIn(duration: 0.6)) { lit = true }
            } else {
                // Three slow breaths, then it fades as the panel closes.
                withAnimation(.easeInOut(duration: 1.1).repeatCount(5, autoreverses: true)) { lit = true }
            }
        }
    }
}
