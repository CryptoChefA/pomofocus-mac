import Foundation
import PomofocusShared
import WidgetKit

extension AppModel {
    func synchronizeWidget() {
        let now = Date()
        let widgetPhase = PomofocusWidgetPhase(rawValue: phase.rawValue) ?? .focus
        let widgetStatus: PomofocusWidgetStatus

        if isBreathing {
            widgetStatus = .breathing
        } else if awaitingNextPhase != nil {
            widgetStatus = .completed
        } else {
            widgetStatus = switch status {
            case .idle: .idle
            case .running: .running
            case .paused: .paused
            case .overtime: .overtime
            }
        }

        // From the exact focused time, not the whole seconds the app shows, so the widget's
        // countdown turns over on the same instant as the menu bar.
        let active = exactActiveSeconds(at: now)
        let runningEndDate: Date? = widgetStatus == .running
            ? now.addingTimeInterval(max(0, Double(plannedSeconds) - active))
            : nil
        let overtimeStartDate: Date? = widgetStatus == .overtime
            ? now.addingTimeInterval(-max(0, active - Double(plannedSeconds)))
            : nil
        let todayRecorded = todayRecordedFocusSeconds
        let activeToday = phase == .focus && status != .idle ? elapsedSeconds : 0
        let cycleTotal = max(1, settings.longBreakEvery)
        let cycleCurrent = min(cycleTotal, completedFocusCycleCount % cycleTotal + 1)

        let snapshot = PomofocusWidgetSnapshot(
            phase: widgetPhase,
            status: widgetStatus,
            taskName: selectedTask?.name ?? (phase == .focus ? "Focus" : phase.title),
            intention: intention.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: now,
            plannedSeconds: max(1, isBreathing ? Self.breathingTotalSeconds : plannedSeconds),
            remainingSeconds: max(0, isBreathing ? breathingRemaining : remainingSeconds),
            elapsedSeconds: max(0, isBreathing ? Self.breathingTotalSeconds - breathingRemaining : elapsedSeconds),
            progress: min(1, max(0, isBreathing
                ? Double(Self.breathingTotalSeconds - breathingRemaining) / Double(Self.breathingTotalSeconds)
                : progress)),
            endDate: runningEndDate,
            overtimeStartDate: overtimeStartDate,
            cycleCurrent: cycleCurrent,
            cycleTotal: cycleTotal,
            todayFocusSeconds: todayRecorded + activeToday,
            theme: {
                let p = ThemeManager.shared.resolved.palette
                return PomofocusWidgetTheme(isDark: p.isDark, background: p.background, ink: p.ink,
                                            secondaryInk: p.secondaryInk, line: p.line, accent: p.accent)
            }(),
            nextTitle: !isBreathing && canAdvanceCycle ? nextActionTitle : nil
        )

        try? PomofocusWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: PomofocusWidgetSnapshot.kind)
        ControlCenterRefresh.reloadIfChanged(snapshot)
    }
}

/// Control Center's timer button shows the action a press will take, so it's redrawn when
/// that changes, not on every save.
@MainActor
private enum ControlCenterRefresh {
    static var lastShown = ""

    static func reloadIfChanged(_ snapshot: PomofocusWidgetSnapshot) {
        guard #available(macOS 26.0, *) else { return }
        let shown = "\(snapshot.phase.rawValue) \(snapshot.status.rawValue) \(snapshot.nextTitle ?? "")"
        guard shown != lastShown else { return }
        lastShown = shown
        ControlCenter.shared.reloadControls(ofKind: PomofocusControl.controlCenterKinds[0])
    }
}
