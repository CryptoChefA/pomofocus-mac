import Foundation

enum InsightsRange: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case quarter
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7D"
        case .month: "30D"
        case .quarter: "90D"
        case .all: "All"
        }
    }

    var dayCount: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all: nil
        }
    }
}

struct HourTotal: Identifiable, Equatable, Sendable {
    let hour: Int
    let seconds: Int
    let averageRating: Double?
    var id: Int { hour }
}

struct WeekdayTotal: Identifiable, Equatable, Sendable {
    let weekday: Int
    let label: String
    let seconds: Int
    var id: Int { weekday }
}

struct MonthTotal: Identifiable, Equatable, Sendable {
    let month: Date
    let seconds: Int
    var id: Date { month }
}

struct TaskRating: Identifiable, Equatable, Sendable {
    let name: String
    let averageRating: Double
    let ratedCount: Int
    var id: String { name }
}

struct OvertimePoint: Identifiable, Equatable, Sendable {
    let date: Date
    let focusSeconds: Int
    let breakSeconds: Int
    var id: Date { date }
}

struct InsightsSnapshot: Equatable, Sendable {
    // Trends
    let dayCount: Int
    let focusSeconds: Int
    let sessionCount: Int
    let activeDays: Int
    let averageSessionSeconds: Int
    let averageActiveDaySeconds: Int
    let goalHitDays: Int
    let goalHitRate: Double
    let thisWeekSeconds: Int
    let lastWeekToDateSeconds: Int
    let lastWeekSeconds: Int
    let months: [MonthTotal]

    // Time of day
    let hours: [HourTotal]
    let weekdays: [WeekdayTotal]
    let peakHour: Int?
    let peakWeekdayLabel: String?

    // Focus quality
    let averageRating: Double?
    let ratedCount: Int
    let completionRate: Double?
    let averagePausedSeconds: Int
    let taskRatings: [TaskRating]

    // Breaks and overtime
    let breakSeconds: Int
    let breakCount: Int
    let skippedBreakCount: Int
    let focusToBreakRatio: Double?
    let averageBreakOvertimeSeconds: Int
    let averageFocusOvertimeSeconds: Int
    let overtimeTrend: [OvertimePoint]
    let overtimeTrendIsWeekly: Bool

    /// Percentage change of this week against the same span of last week.
    var weekChange: Double? {
        guard lastWeekToDateSeconds > 0 else { return nil }
        return Double(thisWeekSeconds - lastWeekToDateSeconds) / Double(lastWeekToDateSeconds)
    }

    static func calculate(
        sessions: [FocusSession],
        breaks: [BreakSession],
        dailyGoalMinutes: Int,
        range: InsightsRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> InsightsSnapshot {
        let today = calendar.startOfDay(for: now)
        let counted = sessions.filter { $0.focusedSeconds > 0 && $0.outcome != .abandoned }
        let firstDay = counted.map { calendar.startOfDay(for: $0.startedAt) }.min() ?? today

        let rangeStart: Date
        if let days = range.dayCount {
            rangeStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        } else {
            rangeStart = min(firstDay, today)
        }
        let filterStart: Date = range == .all ? .distantPast : rangeStart
        let spanDays = calendar.dateComponents([.day], from: rangeStart, to: today).day ?? 0
        let dayCount = max(1, spanDays + 1)

        let inRange = counted.filter { $0.startedAt >= filterStart }
        let breaksInRange = breaks.filter { $0.startedAt >= filterStart && $0.restedSeconds > 0 }

        // Trends
        let focusSeconds = inRange.reduce(0) { $0 + $1.focusedSeconds }
        var dayTotals: [Date: Int] = [:]
        for session in inRange {
            dayTotals[calendar.startOfDay(for: session.startedAt), default: 0] += session.focusedSeconds
        }
        let goalSeconds = max(1, dailyGoalMinutes * 60)
        let goalHitDays = dayTotals.values.filter { $0 >= goalSeconds }.count

        let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart) ?? thisWeekStart
        let lastWeekCutoff = lastWeekStart.addingTimeInterval(now.timeIntervalSince(thisWeekStart))

        func total(from start: Date, to end: Date) -> Int {
            counted
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .reduce(0) { $0 + $1.focusedSeconds }
        }

        let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
        var months: [MonthTotal] = []
        for offset in stride(from: -5, through: 0, by: 1) {
            guard let start = calendar.date(byAdding: .month, value: offset, to: currentMonthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            months.append(MonthTotal(month: start, seconds: total(from: start, to: end)))
        }

        // Time of day
        var hourSeconds = [Int](repeating: 0, count: 24)
        var hourRatingSum = [Int](repeating: 0, count: 24)
        var hourRatingCount = [Int](repeating: 0, count: 24)
        var weekdaySeconds = [Int](repeating: 0, count: 8)

        for session in inRange {
            for interval in resolvedIntervals(for: session) {
                distribute(interval.0, interval.1, into: &hourSeconds, calendar: calendar)
            }
            let weekday = calendar.component(.weekday, from: session.startedAt)
            if weekdaySeconds.indices.contains(weekday) {
                weekdaySeconds[weekday] += session.focusedSeconds
            }
            if let rating = session.focusRating {
                let hour = calendar.component(.hour, from: session.startedAt)
                if hourRatingSum.indices.contains(hour) {
                    hourRatingSum[hour] += rating
                    hourRatingCount[hour] += 1
                }
            }
        }

        let hours = (0..<24).map { hour -> HourTotal in
            let count = hourRatingCount[hour]
            let average: Double? = count > 0 ? Double(hourRatingSum[hour]) / Double(count) : nil
            return HourTotal(hour: hour, seconds: hourSeconds[hour], averageRating: average)
        }

        let symbols = calendar.shortWeekdaySymbols
        let weekdays = (0..<7).map { offset -> WeekdayTotal in
            let weekday = (calendar.firstWeekday - 1 + offset) % 7 + 1
            let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
            return WeekdayTotal(weekday: weekday, label: label, seconds: weekdaySeconds[weekday])
        }

        let peakHourEntry = hours.max { $0.seconds < $1.seconds }
        let peakWeekdayEntry = weekdays.max { $0.seconds < $1.seconds }

        // Focus quality
        let rated = inRange.filter { $0.focusRating != nil }
        let ratingSum = rated.reduce(0) { $0 + ($1.focusRating ?? 0) }
        let completedCount = inRange.filter { $0.outcome == .completed }.count
        let pausedTotal = inRange.reduce(0) { $0 + $1.pausedSeconds }

        let ratedByTask = Dictionary(grouping: rated) { $0.taskName.isEmpty ? "Uncategorized" : $0.taskName }
        let taskRatings = ratedByTask.map { name, group -> TaskRating in
            let sum = group.reduce(0) { $0 + ($1.focusRating ?? 0) }
            return TaskRating(name: name, averageRating: Double(sum) / Double(group.count), ratedCount: group.count)
        }
        .sorted {
            if $0.averageRating == $1.averageRating { return $0.ratedCount > $1.ratedCount }
            return $0.averageRating > $1.averageRating
        }

        // Breaks and overtime
        let breakSeconds = breaksInRange.reduce(0) { $0 + $1.restedSeconds }
        let skipped = breaksInRange.filter(\.wasSkipped).count
        let finishedBreaks = breaksInRange.filter { !$0.wasSkipped }
        let breakOvertimeTotal = finishedBreaks.reduce(0) { $0 + $1.overtimeSeconds }
        let completedSessions = inRange.filter { $0.outcome == .completed }
        let focusOvertimeTotal = completedSessions.reduce(0) { $0 + max(0, $1.focusedSeconds - $1.plannedSeconds) }

        let weekly = dayCount > 31
        func bucket(_ date: Date) -> Date {
            if weekly { return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date) }
            return calendar.startOfDay(for: date)
        }
        var focusOvertimeBuckets: [Date: Int] = [:]
        var breakOvertimeBuckets: [Date: Int] = [:]
        for session in inRange {
            let overtime = max(0, session.focusedSeconds - session.plannedSeconds)
            if overtime > 0 { focusOvertimeBuckets[bucket(session.startedAt), default: 0] += overtime }
        }
        for record in breaksInRange where record.overtimeSeconds > 0 {
            breakOvertimeBuckets[bucket(record.startedAt), default: 0] += record.overtimeSeconds
        }
        let bucketDates = Set(focusOvertimeBuckets.keys).union(breakOvertimeBuckets.keys).sorted()
        let overtimeTrend = bucketDates.map {
            OvertimePoint(
                date: $0,
                focusSeconds: focusOvertimeBuckets[$0, default: 0],
                breakSeconds: breakOvertimeBuckets[$0, default: 0]
            )
        }

        return InsightsSnapshot(
            dayCount: dayCount,
            focusSeconds: focusSeconds,
            sessionCount: inRange.count,
            activeDays: dayTotals.count,
            averageSessionSeconds: inRange.isEmpty ? 0 : focusSeconds / inRange.count,
            averageActiveDaySeconds: dayTotals.isEmpty ? 0 : focusSeconds / dayTotals.count,
            goalHitDays: goalHitDays,
            goalHitRate: Double(goalHitDays) / Double(dayCount),
            thisWeekSeconds: total(from: thisWeekStart, to: .distantFuture),
            lastWeekToDateSeconds: total(from: lastWeekStart, to: lastWeekCutoff),
            lastWeekSeconds: total(from: lastWeekStart, to: thisWeekStart),
            months: months,
            hours: hours,
            weekdays: weekdays,
            peakHour: (peakHourEntry?.seconds ?? 0) > 0 ? peakHourEntry?.hour : nil,
            peakWeekdayLabel: (peakWeekdayEntry?.seconds ?? 0) > 0 ? peakWeekdayEntry?.label : nil,
            averageRating: rated.isEmpty ? nil : Double(ratingSum) / Double(rated.count),
            ratedCount: rated.count,
            completionRate: inRange.isEmpty ? nil : Double(completedCount) / Double(inRange.count),
            averagePausedSeconds: inRange.isEmpty ? 0 : pausedTotal / inRange.count,
            taskRatings: taskRatings,
            breakSeconds: breakSeconds,
            breakCount: breaksInRange.count,
            skippedBreakCount: skipped,
            focusToBreakRatio: breakSeconds > 0 ? Double(focusSeconds) / Double(breakSeconds) : nil,
            averageBreakOvertimeSeconds: finishedBreaks.isEmpty ? 0 : breakOvertimeTotal / finishedBreaks.count,
            averageFocusOvertimeSeconds: completedSessions.isEmpty ? 0 : focusOvertimeTotal / completedSessions.count,
            overtimeTrend: overtimeTrend,
            overtimeTrendIsWeekly: weekly
        )
    }

    /// The stretches a session was actually running, so pauses never count toward an hour.
    private static func resolvedIntervals(for session: FocusSession) -> [(Date, Date)] {
        if let stored = session.activeIntervals {
            let closed: [(Date, Date)] = stored.compactMap { interval in
                guard let end = interval.endedAt, end > interval.startedAt else { return nil }
                return (interval.startedAt, end)
            }
            if !closed.isEmpty { return closed }
        }
        let end = session.startedAt.addingTimeInterval(TimeInterval(session.focusedSeconds))
        return [(session.startedAt, end)]
    }

    /// Splits one stretch of time at every hour boundary and adds each piece to its hour.
    private static func distribute(_ start: Date, _ end: Date, into hours: inout [Int], calendar: Calendar) {
        var cursor = start
        var guardCount = 0
        while cursor < end, guardCount < 10_000 {
            guardCount += 1
            let boundary = calendar.dateInterval(of: .hour, for: cursor)?.end ?? end
            let segmentEnd = min(end, boundary)
            guard segmentEnd > cursor else { break }
            let hour = calendar.component(.hour, from: cursor)
            if hours.indices.contains(hour) {
                hours[hour] += Int(segmentEnd.timeIntervalSince(cursor).rounded())
            }
            cursor = segmentEnd
        }
    }
}
