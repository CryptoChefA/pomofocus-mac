import Foundation

/// Focus per calendar week, for the Dashboard's "Hours by week" chart. Plain data in,
/// plain data out, so it can be checked on its own.
struct WeeklyTotals: Equatable {
    struct Week: Identifiable, Equatable {
        /// The first day of the week, in the user's calendar.
        let start: Date
        let seconds: Int
        /// Blocks run to their full length (a block split across lists counts once).
        let completed: Int
        /// Blocks ended before their planned length.
        let endedEarly: Int
        var id: Date { start }
    }

    /// Oldest first; the last is the week in progress.
    let weeks: [Week]
    /// Last week's focus up to the same point in the week as now, for a fair comparison
    /// with the week in progress.
    var lastWeekToDateSeconds = 0

    var thisWeek: Week? { weeks.last }
    var lastWeek: Week? { weeks.count >= 2 ? weeks[weeks.count - 2] : nil }

    /// The average of the finished weeks that had any focus, so a week off doesn't drag it
    /// down and the half-done current week doesn't either. Nil until there is one.
    var averageSeconds: Int? {
        let finished = weeks.dropLast().filter { $0.seconds > 0 }
        guard !finished.isEmpty else { return nil }
        return finished.reduce(0) { $0 + $1.seconds } / finished.count
    }

    var hasFocus: Bool { weeks.contains { $0.seconds > 0 } }

    static func calculate(sessions: [FocusSession], weeks count: Int = 12, now: Date = Date(),
                          calendar: Calendar = .current) -> WeeklyTotals {
        let thisStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let starts: [Date] = (0..<max(1, count)).reversed().compactMap {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisStart)
        }
        guard let first = starts.first else { return WeeklyTotals(weeks: []) }
        let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisStart) ?? thisStart
        let lastWeekCutoff = lastStart.addingTimeInterval(now.timeIntervalSince(thisStart))

        let counted = sessions.filter { $0.outcome != .abandoned && $0.focusedSeconds > 0 && $0.startedAt >= first }
        let blocks = FocusSession.mergedBlocks(counted)
        func index(for date: Date) -> Int? {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
            return starts.firstIndex(of: start)
        }

        var seconds = Array(repeating: 0, count: starts.count)
        var completed = Array(repeating: 0, count: starts.count)
        var early = Array(repeating: 0, count: starts.count)
        for session in counted {
            if let i = index(for: session.startedAt) { seconds[i] += session.focusedSeconds }
        }
        for block in blocks {
            guard let i = index(for: block.startedAt) else { continue }
            if block.outcome == .completed { completed[i] += 1 } else if block.outcome == .finishedEarly { early[i] += 1 }
        }
        let lastWeekToDate = counted
            .filter { $0.startedAt >= lastStart && $0.startedAt < lastWeekCutoff }
            .reduce(0) { $0 + $1.focusedSeconds }
        return WeeklyTotals(weeks: starts.indices.map {
            Week(start: starts[$0], seconds: seconds[$0], completed: completed[$0], endedEarly: early[$0])
        }, lastWeekToDateSeconds: lastWeekToDate)
    }
}
