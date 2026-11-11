import AppKit
import SwiftUI

// Whether the window a view lives in can be seen at all: not minimised, not on another
// Space, not fully covered, not closed to the menu bar. Views that change every second (the
// dial, the clock, the menu-bar panel) stop redrawing while it can't, and catch up the
// moment it can, so a timer left running behind other windows costs next to nothing.

private struct WindowIsVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var windowIsVisible: Bool {
        get { self[WindowIsVisibleKey.self] }
        set { self[WindowIsVisibleKey.self] = newValue }
    }
}

extension View {
    /// Tells everything inside whether its window is on screen. Put it once at the root of
    /// each window.
    func tracksWindowVisibility() -> some View {
        modifier(WindowVisibilityModifier())
    }
}

private struct WindowVisibilityModifier: ViewModifier {
    @State private var visible = true

    func body(content: Content) -> some View {
        content
            .environment(\.windowIsVisible, visible)
            .background(WindowVisibilityReader { visible = $0 })
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: @MainActor (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: (@MainActor (Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        private func report() {
            guard let window else { return }
            let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
            guard visible != lastReported else { return }
            lastReported = visible
            // Not during the view update that moved this view into its window.
            DispatchQueue.main.async { [onChange] in
                MainActor.assumeIsolated { onChange?(visible) }
            }
        }
    }
}
