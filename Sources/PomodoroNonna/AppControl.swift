import Foundation
import PomofocusShared

/// Widget buttons, Shortcuts and `pomofocus://` links all end up here.
extension AppModel {
    /// Listens for the widget's buttons. The widget runs in its own sandboxed process, so it
    /// posts a distributed notification and the app does the work.
    func startControlObservers() {
        for control in PomofocusControl.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: control.notificationName, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.perform(control) }
            }
        }
    }

    /// Does what was asked only if it still fits what the timer is doing.
    func perform(_ control: PomofocusControl) {
        guard hasLoaded else {
            // Opened by the control itself (the widget launches the app when it isn't
            // running); run it once the saved timer has been restored.
            pendingControl = control
            return
        }
        switch control {
        case .start:
            guard status == .idle, !isBreathing, !canAdvanceCycle else { return }
            start()
        case .pause:
            guard status == .running || status == .overtime else { return }
            togglePause()
        case .resume:
            guard status == .paused else { return }
            togglePause()
        case .toggle:
            if isBreathing || canAdvanceCycle { perform(.next) }
            else if status == .idle { perform(.start) }
            else { togglePause() }
        case .next:
            if isBreathing { skipBreathing() }
            else if canAdvanceCycle { advanceToNextPhase() }
        case .end:
            guard canEndSession else { return }
            endSession()
        case .skipBreak:
            guard phase != .focus || isOvertime else { return }
            skipBreakAndStartFocus()
        }
    }

    func runPendingControl() {
        guard let control = pendingControl else { return }
        pendingControl = nil
        perform(control)
    }
}
