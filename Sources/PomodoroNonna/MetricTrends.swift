import SwiftUI

/// One short "how is this going" line for a dashboard number: which way it moved and
/// whether that's good. Arrows show the direction; green or red shows good or bad.
struct MetricTrend: Equatable, Identifiable {
    enum Direction { case up, down, flat }

    let text: String
    let direction: Direction
    /// nil when the change is neither good nor bad.
    let isGood: Bool?

    var id: String { text }

    var color: Color {
        switch isGood {
        case true?: TrendColors.good
        case false?: TrendColors.bad
        case nil: NonnaTheme.secondaryInk
        }
    }

    var symbol: String {
        switch direction {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .flat: "equal"
        }
    }
}

/// A clear green and red that read on both light and dark themes.
enum TrendColors {
    static let good = Color(red: 0.24, green: 0.72, blue: 0.42)
    static let bad = Color(red: 0.90, green: 0.33, blue: 0.31)
}

/// This week so far against the same stretch of last week, per dashboard number.
enum MetricTrends {
    static func compute(
        sessions: [FocusSession],
        breaks: [BreakSession],
        streak: Int,
        bestStreak: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DashboardMetric: [MetricTrend]] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [:] }
        let elapsed = now.timeIntervalSince(week.start)
        let lastStart = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) ?? week.start.addingTimeInterval(-7 * 86_400)
        let thisRange = week.start..<now
        let lastRange = lastStart..<lastStart.addingTimeInterval(elapsed)

        let counted = sessions.filter { $0.outcome != .abandoned }
        func focus(_ range: Range<Date>) -> Int { counted.filter { range.contains($0.startedAt) }.reduce(0) { $0 + $1.focusedSeconds } }
        func rest(_ range: Range<Date>) -> Int { breaks.filter { range.contains($0.startedAt) }.reduce(0) { $0 + $1.restedSeconds } }
        func overtime(_ range: Range<Date>) -> Int { breaks.filter { range.contains($0.startedAt) }.reduce(0) { $0 + $1.overtimeSeconds } }
        func days(_ range: Range<Date>) -> Int { Set(counted.filter { range.contains($0.startedAt) }.map { calendar.startOfDay(for: $0.startedAt) }).count }
        func blocks(_ range: Range<Date>) -> [FocusSession] { FocusSession.mergedBlocks(sessions.filter { range.contains($0.startedAt) }) }
        func completed(_ range: Range<Date>) -> Int { blocks(range).filter { $0.outcome == .completed }.count }
        func completionRate(_ range: Range<Date>) -> Double? {
            let all = blocks(range)
            return all.isEmpty ? nil : Double(all.filter { $0.outcome == .completed }.count) / Double(all.count)
        }

        var result: [DashboardMetric: [MetricTrend]] = [:]

        result[.focus] = [
            percent(focus(thisRange), focus(lastRange), noun: "focus", higherIsGood: true),
            amount(focus(thisRange), focus(lastRange), unit: .duration, noun: "this week", higherIsGood: true),
        ].compactMap { $0 }

        result[.breakTime] = [
            percent(rest(thisRange), rest(lastRange), noun: "rest", higherIsGood: nil),
            amount(rest(thisRange), rest(lastRange), unit: .duration, noun: "this week", higherIsGood: nil),
        ].compactMap { $0 }

        result[.breakOvertime] = [
            percent(overtime(thisRange), overtime(lastRange), noun: "overtime", higherIsGood: false),
            amount(overtime(thisRange), overtime(lastRange), unit: .duration, noun: "this week", higherIsGood: false),
        ].compactMap { $0 }

        result[.daysUsed] = [
            amount(days(thisRange), days(lastRange), unit: .days, noun: "this week", higherIsGood: true),
        ].compactMap { $0 }

        var rhythm: [MetricTrend] = []
        if streak > 0, streak >= bestStreak {
            rhythm.append(MetricTrend(text: "Your best run yet", direction: .up, isGood: true))
        } else if bestStreak > streak {
            let gap = bestStreak - streak
            rhythm.append(MetricTrend(text: "\(gap) \(gap == 1 ? "day" : "days") to beat your best", direction: .flat, isGood: nil))
        }
        result[.rhythm] = rhythm

        var completion = [amount(completed(thisRange), completed(lastRange), unit: .count, noun: "this week", higherIsGood: true)].compactMap { $0 }
        if let now = completionRate(thisRange), let before = completionRate(lastRange) {
            let points = Int(((now - before) * 100).rounded())
            if points != 0 {
                completion.append(MetricTrend(
                    text: "\(points > 0 ? "Up" : "Down") \(abs(points)) \(abs(points) == 1 ? "point" : "points") in finish rate",
                    direction: points > 0 ? .up : .down,
                    isGood: points > 0
                ))
            }
        }
        result[.completed] = completion
        return result
    }

    private enum Unit { case duration, days, count }

    /// "54% more focus than last week" (or less), when there's something to compare with.
    private static func percent(_ now: Int, _ before: Int, noun: String, higherIsGood: Bool?) -> MetricTrend? {
        guard before > 0 else { return nil }
        let change = Double(now - before) / Double(before)
        let rounded = Int((change * 100).rounded())
        guard rounded != 0 else { return MetricTrend(text: "Same \(noun) as last week", direction: .flat, isGood: nil) }
        let up = rounded > 0
        return MetricTrend(
            text: "\(abs(rounded))% \(up ? "more" : "less") \(noun) than last week",
            direction: up ? .up : .down,
            isGood: higherIsGood.map { $0 == up }
        )
    }

    /// "Up 2h 10m this week" / "Down 1 day this week".
    private static func amount(_ now: Int, _ before: Int, unit: Unit, noun: String, higherIsGood: Bool?) -> MetricTrend? {
        let delta = now - before
        guard now > 0 || before > 0 else { return nil }
        guard delta != 0 else { return MetricTrend(text: "Level with last week", direction: .flat, isGood: nil) }
        let size = abs(delta)
        let text: String = switch unit {
        case .duration: (size / 60).minutesString
        case .days: "\(size) \(size == 1 ? "day" : "days")"
        case .count: "\(size) \(size == 1 ? "block" : "blocks")"
        }
        return MetricTrend(
            text: "\(delta > 0 ? "Up" : "Down") \(text) \(noun)",
            direction: delta > 0 ? .up : .down,
            isGood: higherIsGood.map { $0 == (delta > 0) }
        )
    }
}

/// Fades through a metric's trend lines, one at a time.
struct TrendTicker: View {
    let trends: [MetricTrend]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0

    var body: some View {
        let current = trends.isEmpty ? nil : trends[index % trends.count]
        ZStack(alignment: .leading) {
            if let current {
                HStack(spacing: 5) {
                    Image(systemName: current.symbol)
                        .font(.system(size: 8, weight: .bold))
                    Text(current.text)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(current.color)
                .id(current.id)
                .transition(.opacity)
            }
        }
        .frame(height: 16, alignment: .leading)
        .task(id: trends.count) {
            guard trends.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) { index += 1 }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
