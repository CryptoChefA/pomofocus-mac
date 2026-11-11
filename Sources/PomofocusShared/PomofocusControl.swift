import Foundation

/// Something the timer can be asked to do from outside the app: a widget button, a
/// Shortcut, or a `pomofocus://` link. The app checks each one against the timer's state
/// before acting, so a button pressed on a widget that's a moment out of date does nothing
/// rather than the wrong thing.
public enum PomofocusControl: String, CaseIterable, Sendable {
    case start
    case pause
    case resume
    /// Start, pause or resume, whichever fits. For a single keyboard shortcut.
    case toggle
    /// Skips the breathing ritual, or moves on to the next block when one is waiting.
    case next
    case end
    case skipBreak = "skip-break"

    /// Posted by the widget to the running app. A sandboxed widget can't attach any data to
    /// a distributed notification, so each control has a name of its own.
    public var notificationName: Notification.Name {
        Notification.Name("org.pomodorononna.app.control.\(rawValue)")
    }

    /// `pomofocus://pause` and so on, for Shortcuts and for launching the app when it isn't open.
    public var url: URL { URL(string: "pomofocus://\(rawValue)")! }

    /// The Control Center buttons, so the app can ask for them to be redrawn when the
    /// timer changes state.
    public static let controlCenterKinds = [
        "org.pomodorononna.app.control-center.timer",
        "org.pomodorononna.app.control-center.end",
    ]

    public init?(url: URL) {
        guard url.scheme == "pomofocus", let host = url.host?.lowercased() else { return nil }
        self.init(rawValue: host)
    }
}
