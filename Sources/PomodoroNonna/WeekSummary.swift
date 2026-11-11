import Foundation

/// "Your week": one calm look back at a week of focus, worked out from sessions and mood
/// check-ins. Plain data in, plain data out, so it can be checked on its own.
struct WeekSummary {
    /// One piece of focused time.
    struct Block {
        let start: Date
        let seconds: Int
        let list: String?
    }

    enum TimeOfDay: String {
        case morning, afternoon, evening

        static func of(_ date: Date, calendar: Calendar) -> TimeOfDay {
            let hour = calendar.component(.hour, from: date)
            return hour < 12 ? .morning : hour < 17 ? .afternoon : .evening
        }
    }

    struct Day: Identifiable {
        let day: Date
        let seconds: Int
        var id: Date { day }
    }

    /// The week's first day (midnight), in the calendar's own week.
    let start: Date
    let end: Date
    let days: [Day]
    let totalSeconds: Int
    let previousSeconds: Int
    let blockCount: Int
    let daysFocused: Int
    let bestDay: Day?
    let bestTime: TimeOfDay?
    /// The share of the week's focus that fell in the best time of day, 0 to 1.
    let bestTimeShare: Double
    let topList: (name: String, seconds: Int)?
    let moodCheckIns: Int
    let moodAverage: Double?
    let suggestion: String

    var hasFocus: Bool { totalSeconds > 0 }

    /// The calendar week containing `date`.
    static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func calculate(blocks: [Block], checkIns: [MoodCheckIn], weekStart: Date, calendar: Calendar = .current) -> WeekSummary {
        let start = calendar.startOfDay(for: weekStart)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let previousStart = calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let week = blocks.filter { $0.start >= start && $0.start < end && $0.seconds > 0 }
        let previous = blocks.filter { $0.start >= previousStart && $0.start < start }.reduce(0) { $0 + $1.seconds }

        let days: [Day] = (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            return Day(day: day, seconds: week.filter { $0.start >= day && $0.start < next }.reduce(0) { $0 + $1.seconds })
        }
        let total = week.reduce(0) { $0 + $1.seconds }
        let focusedDays = days.filter { $0.seconds > 0 }
        let best = focusedDays.max { $0.seconds < $1.seconds }

        var byTime: [TimeOfDay: Int] = [:]
        for block in week { byTime[TimeOfDay.of(block.start, calendar: calendar), default: 0] += block.seconds }
        let bestTime = byTime.max { $0.value < $1.value }
        let share = total > 0 ? Double(bestTime?.value ?? 0) / Double(total) : 0

        var byList: [String: Int] = [:]
        for block in week { if let list = block.list, !list.isEmpty { byList[list, default: 0] += block.seconds } }
        let top = byList.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }

        let moods = checkIns.filter { $0.date >= start && $0.date < end }
        let moodAverage = moods.isEmpty ? nil : Double(moods.reduce(0) { $0 + $1.level }) / Double(moods.count)

        let suggestion = suggest(total: total, previous: previous, blocks: week.count, daysFocused: focusedDays.count,
                                 bestTime: bestTime?.key, share: share, moodAverage: moodAverage, moodCount: moods.count)
        return WeekSummary(start: start, end: end, days: days, totalSeconds: total, previousSeconds: previous,
                           blockCount: week.count, daysFocused: focusedDays.count, bestDay: best, bestTime: bestTime?.key,
                           bestTimeShare: share, topList: top.map { ($0.key, $0.value) }, moodCheckIns: moods.count,
                           moodAverage: moodAverage, suggestion: suggestion)
    }

    /// One suggestion, picked from what the week actually shows, kindest first.
    static func suggest(total: Int, previous: Int, blocks: Int, daysFocused: Int, bestTime: TimeOfDay?,
                        share: Double, moodAverage: Double?, moodCount: Int) -> String {
        if let mood = moodAverage, moodCount >= 3, mood <= 3.2 {
            return "It was a heavier week. Next week, a smaller goal and shorter blocks are a good place to start."
        }
        if total == 0 {
            return "A quiet week. One short block is all it takes to get going again."
        }
        if let time = bestTime, blocks >= 4, share >= 0.5 {
            return "Most of your focus happened in the \(time.rawValue). Try giving your hardest task that time next week."
        }
        if daysFocused <= 2 {
            return "You focused on \(daysFocused == 1 ? "one day" : "two days"). A short block on one more day next week is a good next step."
        }
        if previous > 0, Double(total) >= Double(previous) * 1.2 {
            return "That's more than the week before. Keep the same rhythm; there's no need to push further."
        }
        return "A steady week. The days and times that worked this week make a good plan for the next."
    }
}
