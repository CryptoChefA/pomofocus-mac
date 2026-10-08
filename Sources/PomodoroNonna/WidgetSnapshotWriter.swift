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

        let runningEndDate: Date? = widgetStatus == .running
            ? now.addingTimeInterval(TimeInterval(max(0, remainingSeconds)))
            : nil
        let overtimeSeconds = max(0, elapsedSeconds - plannedSeconds)
        let overtimeStartDate: Date? = widgetStatus == .overtime
            ? now.addingTimeInterval(TimeInterval(-overtimeSeconds))
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
            todayFocusSeconds: todayRecorded + activeToday
        )

        try? PomofocusWidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: PomofocusWidgetSnapshot.kind)
    }
}
