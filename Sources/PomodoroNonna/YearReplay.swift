import Foundation

/// "Your year in focus": the whole year (or the year so far) told as a few cards, like a
/// yearly wrap-up. Plain data in, plain data out, so it can be checked on its own.
struct YearReplay {
    struct Month: Identifiable {
        let month: Date
        let seconds: Int
        var id: Date { month }
    }

    struct Ranked {
        let name: String
        let seconds: Int
    }

    let year: Int
    /// January 1st of the year.
    let start: Date
    /// Where the numbers stop: the end of the year, or now if it isn't over.
    let end: Date
    let totalSeconds: Int
    let blockCount: Int
    let daysFocused: Int
    /// All twelve months, empty ones included.
    let months: [Month]
    let bestMonth: Month?
    let bestDay: (day: Date, seconds: Int)?
    /// Up to three lists, most time first.
    let topLists: [Ranked]
    let listCount: Int
    /// Share of the year's focus in the morning, afternoon and evening, 0 to 1.
    let timeShares: [WeekSummary.TimeOfDay: Double]
    let longestStreak: Int
    /// The last day of the longest streak.
    let streakEnd: Date?
    let longestBlock: (start: Date, seconds: Int)?
    let firstBlock: Date?

    let moodCount: Int
    let moodAverage: Double?
    /// Pleasant, neutral and unpleasant check-ins as shares, 0 to 1.
    let moodMix: (pleasant: Double, neutral: Double, unpleasant: Double)
    let topFeelings: [String]
    /// The month with the brightest average, among months with at least three check-ins.
    let brightestMonth: Date?

    var hasFocus: Bool { totalSeconds > 0 }
    /// Enough check-ins to say something about the year's moods without overreaching.
    var hasMoods: Bool { moodCount >= 5 }

    var bestTime: WeekSummary.TimeOfDay? {
        timeShares.max { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }?.key
    }

    /// The year's rhythm in a sentence.
    var rhythm: String {
        guard let time = bestTime, let share = timeShares[time] else { return "" }
        let percent = Int((share * 100).rounded())
        if share < 0.45 { return "You spread your focus across the day. No time of day had more than \(percent)%." }
        switch time {
        case .morning: return "You're a morning person. \(percent)% of your focus happened before noon."
        case .afternoon: return "You did your best work after lunch. \(percent)% of your focus happened in the afternoon."
        case .evening: return "You're a night owl. \(percent)% of your focus happened after 5 pm."
        }
    }

    /// A sense of scale for the total, kept plain.
    var scale: String? {
        let hours = totalSeconds / 3600
        if hours >= 48 { return "That's more than \(hours / 24) full days of focus." }
        if hours >= 24 { return "That's more than a full day of focus." }
        return nil
    }

    /// The Replay shown for `date`: in December and the first two weeks of January the
    /// finished (or nearly finished) year, otherwise nil, so the year-so-far view is used.
    static func wrapUpYear(for date: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        if month == 12 { return year }
        if month == 1, day <= 14 { return year - 1 }
        return nil
    }

    static func calculate(blocks: [WeekSummary.Block], checkIns: [MoodCheckIn], year: Int,
                          now: Date = Date(), calendar: Calendar = .current) -> YearReplay {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let yearEnd = calendar.date(byAdding: .year, value: 1, to: start) ?? now
        let end = min(yearEnd, max(start, now))
        let inYear = blocks.filter { $0.start >= start && $0.start < end && $0.seconds > 0 }
        let total = inYear.reduce(0) { $0 + $1.seconds }

        var byDay: [Date: Int] = [:]
        for block in inYear { byDay[calendar.startOfDay(for: block.start), default: 0] += block.seconds }
        let bestDay = byDay.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }

        let months: [Month] = (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: start),
                  let next = calendar.date(byAdding: .month, value: 1, to: month) else { return nil }
            return Month(month: month, seconds: inYear.filter { $0.start >= month && $0.start < next }.reduce(0) { $0 + $1.seconds })
        }
        let bestMonth = months.filter { $0.seconds > 0 }.max { $0.seconds != $1.seconds ? $0.seconds < $1.seconds : $0.month > $1.month }

        var byList: [String: Int] = [:]
        for block in inYear { if let list = block.list, !list.isEmpty { byList[list, default: 0] += block.seconds } }
        let ranked = byList.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(3).map { Ranked(name: $0.key, seconds: $0.value) }

        var byTime: [WeekSummary.TimeOfDay: Int] = [:]
        for block in inYear { byTime[WeekSummary.TimeOfDay.of(block.start, calendar: calendar), default: 0] += block.seconds }
        let shares = total > 0 ? byTime.mapValues { Double($0) / Double(total) } : [:]

        // Consecutive days with any focus.
        var longest = 0, run = 0
        var streakEnd: Date?
        var previous: Date?
        for day in byDay.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            if run > longest { longest = run; streakEnd = day }
            previous = day
        }
        let longestBlock = inYear.max { $0.seconds != $1.seconds ? $0.seconds < $1.seconds : $0.start > $1.start }

        let moods = checkIns.filter { $0.date >= start && $0.date < end }
        let moodAverage = moods.isEmpty ? nil : Double(moods.reduce(0) { $0 + $1.level }) / Double(moods.count)
        let count = Double(max(1, moods.count))
        let mix = (pleasant: Double(moods.filter { MoodScale.isPleasant($0.level) }.count) / count,
                   neutral: Double(moods.filter { $0.level == 4 }.count) / count,
                   unpleasant: Double(moods.filter { MoodScale.isUnpleasant($0.level) }.count) / count)
        var words: [String: Int] = [:]
        for checkIn in moods { for feeling in checkIn.feelings { words[feeling, default: 0] += 1 } }
        let feelings = words.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map(\.key)
        var moodMonths: [Date: [Int]] = [:]
        for checkIn in moods {
            let month = calendar.dateInterval(of: .month, for: checkIn.date)?.start ?? checkIn.date
            moodMonths[month, default: []].append(checkIn.level)
        }
        let brightest = moodMonths.filter { $0.value.count >= 3 }
            .max { lhs, rhs in
                let a = Double(lhs.value.reduce(0, +)) / Double(lhs.value.count)
                let b = Double(rhs.value.reduce(0, +)) / Double(rhs.value.count)
                return a != b ? a < b : lhs.key > rhs.key
            }?.key

        return YearReplay(
            year: year, start: start, end: end, totalSeconds: total, blockCount: inYear.count, daysFocused: byDay.count,
            months: months, bestMonth: bestMonth, bestDay: bestDay.map { ($0.key, $0.value) },
            topLists: ranked, listCount: byList.count, timeShares: shares,
            longestStreak: longest, streakEnd: streakEnd,
            longestBlock: longestBlock.map { ($0.start, $0.seconds) },
            firstBlock: inYear.map(\.start).min(),
            moodCount: moods.count, moodAverage: moodAverage, moodMix: mix, topFeelings: feelings,
            brightestMonth: brightest
        )
    }
}
