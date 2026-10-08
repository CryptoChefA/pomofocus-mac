import Foundation

struct DeepDiveDay: Identifiable, Equatable, Sendable {
    let date: Date
    let focusSeconds: Int
    let rollingFocusSeconds: Int
    let breakSeconds: Int
    let plannedBreakSeconds: Int
    let breakOvertimeSeconds: Int
    let focusOvertimeSeconds: Int
    let pausedSeconds: Int
    let completedCount: Int
    let earlyCount: Int
    let abandonedCount: Int

    var id: Date { date }
    var sessionCount: Int { completedCount + earlyCount + abandonedCount }
}

struct DeepDiveTaskTotal: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let colorHex: String
    let seconds: Int
    let sessions: Int
}

/// A dense, range-specific view of the local session database used by every dashboard drill-down.
/// Nothing is inferred from network data and no event is written back to another service.
struct DeepDiveSnapshot: Equatable, Sendable {
    let range: InsightsRange
    let days: [DeepDiveDay]
    let tasks: [DeepDiveTaskTotal]
    let hours: [HourTotal]
    let weekdays: [WeekdayTotal]

    let totalFocusSeconds: Int
    let totalBreakSeconds: Int
    let totalPlannedBreakSeconds: Int
    let totalBreakOvertimeSeconds: Int
    let totalFocusOvertimeSeconds: Int
    let totalPausedSeconds: Int
    let averageSessionSeconds: Int
    let medianSessionSeconds: Int
    let longestSessionSeconds: Int
    let averageBreakSeconds: Int

    let activeDays: Int
    let goalHitDays: Int
    let completedCount: Int
    let earlyCount: Int
    let abandonedCount: Int
    let skippedBreakCount: Int
    let breakEarlyCount: Int
    let breakOnPlanCount: Int
    let breakOvertimeCount: Int
    let deepSessionCount: Int

    let currentStreak: Int
    let longestStreak: Int
    let lifetimeUsedDays: Int
    let consistencyScore: Int
    let weekChange: Double?
    let averageRating: Double?
    let ratedCount: Int

    var dayCount: Int { days.count }
    var sessionCount: Int { completedCount + earlyCount }
    var recordedSessionCount: Int { sessionCount + abandonedCount }
    var breakCount: Int { skippedBreakCount + breakEarlyCount + breakOnPlanCount + breakOvertimeCount }
    var activeRate: Double { days.isEmpty ? 0 : Double(activeDays) / Double(days.count) }
    var goalHitRate: Double { days.isEmpty ? 0 : Double(goalHitDays) / Double(days.count) }
    var completionRate: Double { recordedSessionCount == 0 ? 0 : Double(completedCount) / Double(recordedSessionCount) }
    var pauseRatio: Double {
        let total = totalFocusSeconds + totalPausedSeconds
        return total == 0 ? 0 : Double(totalPausedSeconds) / Double(total)
    }
    var breakOvertimeRate: Double {
        totalBreakSeconds == 0 ? 0 : Double(totalBreakOvertimeSeconds) / Double(totalBreakSeconds)
    }
    var focusToBreakRatio: Double? {
        totalBreakSeconds > 0 ? Double(totalFocusSeconds) / Double(totalBreakSeconds) : nil
    }
    var deepWorkShare: Double { sessionCount == 0 ? 0 : Double(deepSessionCount) / Double(sessionCount) }
    var averageActiveDaySeconds: Int { activeDays == 0 ? 0 : totalFocusSeconds / activeDays }
    var averageBreakOvertimeSeconds: Int { breakOvertimeCount == 0 ? 0 : totalBreakOvertimeSeconds / breakOvertimeCount }
    var bestDay: DeepDiveDay? { days.max { $0.focusSeconds < $1.focusSeconds } }
    var largestBreakOvertimeSeconds: Int { days.map(\.breakOvertimeSeconds).max() ?? 0 }
    var peakHour: HourTotal? { hours.max { $0.seconds < $1.seconds }.flatMap { $0.seconds > 0 ? $0 : nil } }
    var peakWeekday: WeekdayTotal? { weekdays.max { $0.seconds < $1.seconds }.flatMap { $0.seconds > 0 ? $0 : nil } }
    var topTaskShare: Double {
        guard totalFocusSeconds > 0, let first = tasks.first else { return 0 }
        return Double(first.seconds) / Double(totalFocusSeconds)
    }

    static func calculate(
        sessions: [FocusSession],
        breaks: [BreakSession],
        tasks: [FocusTask],
        dailyGoalMinutes: Int,
        range: InsightsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> DeepDiveSnapshot {
        let today = calendar.startOfDay(for: now)
        let rangeDays = range.dayCount ?? max(
            1,
            calendar.dateComponents(
                [.day],
                from: sessions.map { calendar.startOfDay(for: $0.startedAt) }.min() ?? today,
                to: today
            ).day.map { $0 + 1 } ?? 1
        )
        let start = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let sessionsInRange = sessions.filter { $0.startedAt >= start && $0.startedAt < end }
        let productive = sessionsInRange.filter { $0.focusedSeconds > 0 && $0.outcome != .abandoned }
        let breaksInRange = breaks.filter { $0.startedAt >= start && $0.startedAt < end && ($0.restedSeconds > 0 || $0.wasSkipped) }
        let goalSeconds = max(1, dailyGoalMinutes * 60)

        let sessionsByDay = Dictionary(grouping: sessionsInRange) { calendar.startOfDay(for: $0.startedAt) }
        let productiveByDay = Dictionary(grouping: productive) { calendar.startOfDay(for: $0.startedAt) }
        let breaksByDay = Dictionary(grouping: breaksInRange) { calendar.startOfDay(for: $0.startedAt) }

        var rawDays: [(date: Date, focus: Int, breaks: Int, plannedBreak: Int, breakOT: Int, focusOT: Int, paused: Int, completed: Int, early: Int, abandoned: Int)] = []
        for offset in 0..<rangeDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let productiveSessions = productiveByDay[day, default: []]
            let everySession = sessionsByDay[day, default: []]
            let dayBreaks = breaksByDay[day, default: []]
            rawDays.append((
                date: day,
                focus: productiveSessions.reduce(0) { $0 + $1.focusedSeconds },
                breaks: dayBreaks.reduce(0) { $0 + $1.restedSeconds },
                plannedBreak: dayBreaks.reduce(0) { $0 + min($1.restedSeconds, $1.plannedSeconds) },
                breakOT: dayBreaks.reduce(0) { $0 + $1.overtimeSeconds },
                focusOT: productiveSessions.reduce(0) { $0 + max(0, $1.focusedSeconds - $1.plannedSeconds) },
                paused: productiveSessions.reduce(0) { $0 + $1.pausedSeconds },
                completed: everySession.filter { $0.outcome == .completed }.count,
                early: everySession.filter { $0.outcome == .finishedEarly }.count,
                abandoned: everySession.filter { $0.outcome == .abandoned }.count
            ))
        }

        let days = rawDays.enumerated().map { index, value -> DeepDiveDay in
            let lower = max(0, index - 6)
            let window = rawDays[lower...index]
            let rolling = window.reduce(0) { $0 + $1.focus } / max(1, window.count)
            return DeepDiveDay(
                date: value.date,
                focusSeconds: value.focus,
                rollingFocusSeconds: rolling,
                breakSeconds: value.breaks,
                plannedBreakSeconds: value.plannedBreak,
                breakOvertimeSeconds: value.breakOT,
                focusOvertimeSeconds: value.focusOT,
                pausedSeconds: value.paused,
                completedCount: value.completed,
                earlyCount: value.early,
                abandonedCount: value.abandoned
            )
        }

        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let groupedTasks = Dictionary(grouping: productive) { session in
            session.taskID?.uuidString ?? "name:\(session.taskName.lowercased())"
        }
        let taskTotals = groupedTasks.map { key, group -> DeepDiveTaskTotal in
            let first = group[0]
            let task = first.taskID.flatMap { taskMap[$0] }
            return DeepDiveTaskTotal(
                id: key,
                name: task?.name ?? (first.taskName.isEmpty ? "Uncategorized" : first.taskName),
                colorHex: task?.colorHex ?? "8D8379",
                seconds: group.reduce(0) { $0 + $1.focusedSeconds },
                sessions: group.count
            )
        }.sorted { $0.seconds > $1.seconds }

        let sessionDurations = productive.map(\.focusedSeconds).sorted()
        let totalFocus = sessionDurations.reduce(0, +)
        let median: Int
        if sessionDurations.isEmpty {
            median = 0
        } else if sessionDurations.count.isMultiple(of: 2) {
            let upper = sessionDurations.count / 2
            median = (sessionDurations[upper - 1] + sessionDurations[upper]) / 2
        } else {
            median = sessionDurations[sessionDurations.count / 2]
        }

        let insights = InsightsSnapshot.calculate(
            sessions: sessions,
            breaks: breaks,
            dailyGoalMinutes: dailyGoalMinutes,
            range: range,
            now: now,
            calendar: calendar
        )
        let lifetime = AnalyticsSnapshot.calculate(sessions: sessions, tasks: tasks, now: now, calendar: calendar)

        let activeTotals = days.map(\.focusSeconds).filter { $0 > 0 }
        let activityRate = Double(activeTotals.count) / Double(max(1, days.count))
        let regularity: Double
        if activeTotals.count < 2 {
            regularity = activeTotals.isEmpty ? 0 : 1
        } else {
            let mean = Double(activeTotals.reduce(0, +)) / Double(activeTotals.count)
            let meanDeviation = activeTotals.reduce(0.0) { $0 + abs(Double($1) - mean) } / Double(activeTotals.count)
            regularity = max(0, 1 - min(1, meanDeviation / max(1, mean)))
        }
        let consistencyScore = Int((100 * (activityRate * 0.62 + regularity * 0.38)).rounded())

        let twoWeeksStart = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        let previousWeekEnd = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let recentSessions = sessions.filter { $0.focusedSeconds > 0 && $0.outcome != .abandoned }
        let priorWeek = recentSessions.filter { $0.startedAt >= twoWeeksStart && $0.startedAt < previousWeekEnd }.reduce(0) { $0 + $1.focusedSeconds }
        let latestWeek = recentSessions.filter { $0.startedAt >= previousWeekEnd && $0.startedAt < end }.reduce(0) { $0 + $1.focusedSeconds }
        let weekChange = priorWeek > 0 ? Double(latestWeek - priorWeek) / Double(priorWeek) : nil

        let completed = sessionsInRange.filter { $0.outcome == .completed }.count
        let early = sessionsInRange.filter { $0.outcome == .finishedEarly }.count
        let abandoned = sessionsInRange.filter { $0.outcome == .abandoned }.count
        let skipped = breaksInRange.filter(\.wasSkipped).count
        let finishedBreaks = breaksInRange.filter { !$0.wasSkipped }
        let earlyBreaks = finishedBreaks.filter { $0.restedSeconds < $0.plannedSeconds }.count
        let overtimeBreaks = finishedBreaks.filter { $0.overtimeSeconds > 0 }.count
        let onPlanBreaks = max(0, finishedBreaks.count - earlyBreaks - overtimeBreaks)
        let ratings = productive.compactMap(\.focusRating)

        return DeepDiveSnapshot(
            range: range,
            days: days,
            tasks: taskTotals,
            hours: insights.hours,
            weekdays: insights.weekdays,
            totalFocusSeconds: totalFocus,
            totalBreakSeconds: breaksInRange.reduce(0) { $0 + $1.restedSeconds },
            totalPlannedBreakSeconds: breaksInRange.reduce(0) { $0 + min($1.restedSeconds, $1.plannedSeconds) },
            totalBreakOvertimeSeconds: breaksInRange.reduce(0) { $0 + $1.overtimeSeconds },
            totalFocusOvertimeSeconds: productive.reduce(0) { $0 + max(0, $1.focusedSeconds - $1.plannedSeconds) },
            totalPausedSeconds: productive.reduce(0) { $0 + $1.pausedSeconds },
            averageSessionSeconds: productive.isEmpty ? 0 : totalFocus / productive.count,
            medianSessionSeconds: median,
            longestSessionSeconds: sessionDurations.last ?? 0,
            averageBreakSeconds: breaksInRange.isEmpty ? 0 : breaksInRange.reduce(0) { $0 + $1.restedSeconds } / breaksInRange.count,
            activeDays: activeTotals.count,
            goalHitDays: days.filter { $0.focusSeconds >= goalSeconds }.count,
            completedCount: completed,
            earlyCount: early,
            abandonedCount: abandoned,
            skippedBreakCount: skipped,
            breakEarlyCount: earlyBreaks,
            breakOnPlanCount: onPlanBreaks,
            breakOvertimeCount: overtimeBreaks,
            deepSessionCount: productive.filter { $0.focusedSeconds >= 3_000 }.count,
            currentStreak: lifetime.currentStreak,
            longestStreak: lifetime.longestStreak,
            lifetimeUsedDays: lifetime.usedDays,
            consistencyScore: consistencyScore,
            weekChange: weekChange,
            averageRating: ratings.isEmpty ? nil : Double(ratings.reduce(0, +)) / Double(ratings.count),
            ratedCount: ratings.count
        )
    }
}
