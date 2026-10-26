import Foundation

/// A day's focus, summed up as one number out of 100, plus the parts that make it up so
/// the number is never a mystery. It's a mirror for your own habits, not a clinical measure.
struct FocusScore: Equatable, Sendable {
    struct Part: Identifiable, Equatable, Sendable {
        enum Kind: String, Sendable { case time, followThrough, interruptions, breaks, depth }
        let kind: Kind
        let title: String
        let points: Double
        let maxPoints: Double
        /// What happened, in plain words ("1h 20m of your 2h goal").
        let detail: String
        /// What would raise this part tomorrow.
        let tip: String

        var id: Kind { kind }
        var fraction: Double { maxPoints > 0 ? points / maxPoints : 0 }
    }

    let day: Date
    let total: Int
    let parts: [Part]

    var label: String { Self.label(for: total) }

    /// The part with the most room to grow, for the "what to work on" line.
    var weakest: Part? { parts.min { $0.fraction < $1.fraction } }

    static func label(for score: Int) -> String {
        switch score {
        case 85...: "Locked in"
        case 70..<85: "Strong"
        case 50..<70: "Building"
        case 25..<50: "Warming up"
        default: "Getting started"
        }
    }

    /// Overtime past this counts for nothing: a timer left running while you were away
    /// shouldn't make a day look better.
    static let overtimeAllowance = 15 * 60

    /// The score for one calendar day, or nil if no focus block was started that day.
    static func compute(
        day: Date,
        sessions: [FocusSession],
        breaks: [BreakSession],
        goalMinutes: Int,
        calendar: Calendar = .current
    ) -> FocusScore? {
        let blocks = sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: day) }
            .sorted { $0.startedAt < $1.startedAt }
        guard !blocks.isEmpty else { return nil }
        let rests = breaks.filter { calendar.isDate($0.startedAt, inSameDayAs: day) }

        // 1. Time focused against the daily goal (40).
        let counted = blocks
            .filter { $0.outcome != .abandoned }
            .reduce(0) { $0 + min($1.focusedSeconds, $1.plannedSeconds + overtimeAllowance) }
        let goal = max(1, goalMinutes) * 60
        let timeFraction = min(1, Double(counted) / Double(goal))
        let time = Part(
            kind: .time, title: "Time focused",
            points: 40 * timeFraction, maxPoints: 40,
            detail: "\((counted / 60).minutesString) of your \(goalMinutes.minutesString) goal",
            tip: timeFraction >= 1 ? "Goal reached. Keep the same rhythm tomorrow."
                : "Another \(((blocks.last?.plannedSeconds ?? 1500) / 60).minutesString) block would take you to \(min(100, Int(((Double(counted) + Double(blocks.last?.plannedSeconds ?? 1500)) / Double(goal) * 100).rounded())))% of your goal."
        )

        // 2. Follow-through: blocks finished as planned (25).
        let finishScores = blocks.map { block -> Double in
            switch block.outcome {
            case .completed: return 1
            case .abandoned: return 0
            default: return min(1, Double(block.focusedSeconds) / Double(max(1, block.plannedSeconds)))
            }
        }
        let finished = blocks.filter { $0.outcome == .completed }.count
        let followFraction = finishScores.reduce(0, +) / Double(blocks.count)
        let follow = Part(
            kind: .followThrough, title: "Follow-through",
            points: 25 * followFraction, maxPoints: 25,
            detail: "\(finished) of \(blocks.count) \(blocks.count == 1 ? "block" : "blocks") finished",
            tip: followFraction >= 0.9 ? "You finish what you start. Nice."
                : "Try a shorter block you know you can finish; finishing builds the habit."
        )

        // 3. Few interruptions: pauses per block (15). Each pause per block costs a third.
        let pauses = blocks.reduce(0) { $0 + max(0, ($1.activeIntervals?.count ?? 1) - 1) }
        let pausesPerBlock = Double(pauses) / Double(blocks.count)
        let calmFraction = max(0, 1 - pausesPerBlock / 3)
        let calm = Part(
            kind: .interruptions, title: "Few interruptions",
            points: 15 * calmFraction, maxPoints: 15,
            detail: pauses == 0 ? "No pauses" : "\(pauses) \(pauses == 1 ? "pause" : "pauses") across \(blocks.count) \(blocks.count == 1 ? "block" : "blocks")",
            tip: calmFraction >= 0.9 ? "Hardly any pauses. Your setup is working."
                : "Put the phone in another room and close extra tabs before you start."
        )

        // 4. Breaks that recharge: taken between blocks, and back on time (10).
        let expected = max(0, blocks.count - 1)
        let onTime = min(expected, rests.filter { !$0.wasSkipped && $0.overtimeSeconds <= 5 * 60 }.count)
        let breakFraction = expected == 0 ? 1 : min(1, Double(onTime) / Double(expected))
        let late = rests.filter { $0.overtimeSeconds > 5 * 60 }.count
        let breaksPart = Part(
            kind: .breaks, title: "Breaks that recharge",
            points: 10 * breakFraction, maxPoints: 10,
            detail: expected == 0 ? "Not needed yet with one block"
                : "\(onTime) of \(expected) \(expected == 1 ? "break" : "breaks") taken and back on time\(late > 0 ? " · \(late) ran long" : "")",
            tip: breakFraction >= 0.9 ? "Good breaks make the next block easier."
                : "Take the break, step away from the screen, and come back when it ends."
        )

        // 5. Depth: the longest unbroken stretch, against your block length (10).
        let longest = blocks.compactMap { block -> TimeInterval? in
            if let intervals = block.activeIntervals, !intervals.isEmpty {
                return intervals.map { $0.duration(through: block.endedAt) }.max()
            }
            return TimeInterval(block.focusedSeconds)
        }.max() ?? 0
        let target = Double(blocks.map(\.plannedSeconds).max() ?? 1500)
        let stretch = min(longest, target + Double(overtimeAllowance))
        let depthFraction = min(1, stretch / max(1, target))
        let depth = Part(
            kind: .depth, title: "Deep stretch",
            points: 10 * depthFraction, maxPoints: 10,
            detail: "Longest unbroken stretch: \((Int(stretch) / 60).minutesString)",
            tip: depthFraction >= 0.9 ? "You held a full block without stopping."
                : "Aim for one block today with no pauses at all."
        )

        let parts = [time, follow, calm, breaksPart, depth]
        let total = Int(parts.reduce(0) { $0 + $1.points }.rounded())
        return FocusScore(day: calendar.startOfDay(for: day), total: min(100, max(0, total)), parts: parts)
    }

    /// Scores for the last `days` days ending today, oldest first; nil where nothing was started.
    static func history(
        days: Int,
        endingOn today: Date = Date(),
        sessions: [FocusSession],
        breaks: [BreakSession],
        goalMinutes: Int,
        calendar: Calendar = .current
    ) -> [(day: Date, score: FocusScore?)] {
        let start = calendar.startOfDay(for: today)
        return (0..<days).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return (day, compute(day: day, sessions: sessions, breaks: breaks, goalMinutes: goalMinutes, calendar: calendar))
        }
    }
}

// MARK: - Runaway timers

/// Timers that kept running for a long time after their planned length, almost always
/// because someone walked away. These helpers find them and trim them back.
enum RunawayTimers {
    /// Overtime beyond this is treated as a forgotten timer.
    static let threshold = 60 * 60

    static func isRunaway(_ session: FocusSession) -> Bool {
        session.outcome != .abandoned && session.focusedSeconds - session.plannedSeconds > threshold
    }

    static func isRunaway(_ rest: BreakSession) -> Bool {
        rest.overtimeSeconds > threshold
    }

    /// Cuts a block back to its planned length (keeping any pauses before that point).
    static func trimmed(_ session: FocusSession) -> FocusSession {
        var session = session
        let (intervals, end) = truncate(session.activeIntervals, startedAt: session.startedAt, keeping: session.plannedSeconds)
        session.activeIntervals = intervals
        session.focusedSeconds = session.plannedSeconds
        session.endedAt = end ?? session.startedAt.addingTimeInterval(TimeInterval(session.plannedSeconds + session.pausedSeconds))
        if intervals != nil { session.pausedSeconds = max(0, Int(session.endedAt.timeIntervalSince(session.startedAt)) - session.plannedSeconds) }
        if session.outcome == .finishedEarly { session.outcome = .completed }
        return session
    }

    static func trimmed(_ rest: BreakSession) -> BreakSession {
        var rest = rest
        let (intervals, end) = truncate(rest.activeIntervals, startedAt: rest.startedAt, keeping: rest.plannedSeconds)
        rest.activeIntervals = intervals
        rest.restedSeconds = rest.plannedSeconds
        rest.endedAt = end ?? rest.startedAt.addingTimeInterval(TimeInterval(rest.plannedSeconds + rest.pausedSeconds))
        if intervals != nil { rest.pausedSeconds = max(0, Int(rest.endedAt.timeIntervalSince(rest.startedAt)) - rest.plannedSeconds) }
        return rest
    }

    /// Keeps the first `seconds` of active time and drops the rest.
    static func truncate(_ intervals: [ActivityInterval]?, startedAt: Date, keeping seconds: Int) -> ([ActivityInterval]?, Date?) {
        guard let intervals, !intervals.isEmpty else { return (nil, nil) }
        var left = TimeInterval(seconds)
        var kept: [ActivityInterval] = []
        for interval in intervals {
            guard left > 0, let end = interval.endedAt else { break }
            let length = end.timeIntervalSince(interval.startedAt)
            if length <= left {
                kept.append(interval)
                left -= length
            } else {
                let cut = interval.startedAt.addingTimeInterval(left)
                kept.append(ActivityInterval(startedAt: interval.startedAt, endedAt: cut))
                left = 0
            }
        }
        return (kept, kept.last?.endedAt)
    }
}
