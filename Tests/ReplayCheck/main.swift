import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); failures += 1 }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
func day(_ month: Int, _ day: Int, _ hour: Int = 9, year: Int = 2026) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
typealias B = WeekSummary.Block
let now = day(11, 5, 12)

// Nothing yet
let empty = YearReplay.calculate(blocks: [], checkIns: [], year: 2026, now: now, calendar: calendar)
check(!empty.hasFocus && empty.months.count == 12 && empty.bestMonth == nil && empty.longestStreak == 0, "an empty year")

var blocks: [B] = [
    // A three-day streak in March, mornings
    B(start: day(3, 2), seconds: 1500, list: "Calculus"), B(start: day(3, 3), seconds: 1500, list: "Calculus"),
    B(start: day(3, 4), seconds: 3000, list: "Chemistry"),
    // October is the biggest month, with a long evening block
    B(start: day(10, 10, 20), seconds: 5400, list: "Essay"), B(start: day(10, 11, 9), seconds: 1500, list: "Calculus"),
    B(start: day(10, 20, 10), seconds: 1500, list: "Calculus"),
    // Not counted: last year, next week, and nothing focused
    B(start: day(12, 30, year: 2025), seconds: 9000, list: "Old"), B(start: day(11, 12), seconds: 9000, list: "Future"),
    B(start: day(4, 1), seconds: 0, list: "Empty"),
]
let r = YearReplay.calculate(blocks: blocks, checkIns: [], year: 2026, now: now, calendar: calendar)
check(r.totalSeconds == 14400 && r.blockCount == 6, "only this year's blocks up to now (\(r.totalSeconds))")
check(r.daysFocused == 6, "six days with focus")
check(r.bestMonth.map { calendar.component(.month, from: $0.month) } == 10 && r.bestMonth?.seconds == 8400, "October was the biggest month")
check(r.topLists.map(\.name) == ["Calculus", "Essay", "Chemistry"] && r.topLists.first?.seconds == 6000, "lists ranked by time")
check(r.listCount == 3, "three lists")
check(r.longestStreak == 3 && r.streakEnd == calendar.startOfDay(for: day(3, 4)), "the March streak is the longest")
check(r.longestBlock?.seconds == 5400, "the longest block")
check(r.bestDay?.seconds == 5400, "the best day")
check(r.firstBlock == day(3, 2), "the first block of the year")
check(r.bestTime == .morning && r.rhythm.contains("morning person"), "a morning person (\(r.rhythm))")
check(r.scale == nil, "four hours gets no scale line")

// A streak running over a month boundary still counts
let edge = YearReplay.calculate(blocks: [B(start: day(1, 31), seconds: 600, list: nil), B(start: day(2, 1), seconds: 600, list: nil)],
                                checkIns: [], year: 2026, now: now, calendar: calendar)
check(edge.longestStreak == 2, "streaks cross months")
check(edge.topLists.isEmpty, "no lists, no ranking")

// Spread across the day
let spread = YearReplay.calculate(blocks: [B(start: day(5, 1, 9), seconds: 1000, list: nil), B(start: day(5, 2, 14), seconds: 1000, list: nil),
                                           B(start: day(5, 3, 20), seconds: 1000, list: nil)], checkIns: [], year: 2026, now: now, calendar: calendar)
check(spread.rhythm.contains("spread"), "an even spread (\(spread.rhythm))")

// Moods
var moods = (1...4).map { MoodCheckIn(date: day(6, $0, 21), level: 6, feelings: ["Calm", "Focused"]) }
moods += (1...3).map { MoodCheckIn(date: day(9, $0, 21), level: 2, feelings: ["Stressed"]) }
moods.append(MoodCheckIn(date: day(9, 10, 21), level: 4, feelings: ["Calm"]))
let m = YearReplay.calculate(blocks: blocks, checkIns: moods, year: 2026, now: now, calendar: calendar)
check(m.hasMoods && m.moodCount == 8, "eight check-ins")
check(abs(m.moodMix.pleasant - 0.5) < 0.001 && abs(m.moodMix.unpleasant - 0.375) < 0.001 && abs(m.moodMix.neutral - 0.125) < 0.001, "the mood mix")
check(m.topFeelings.first == "Calm" && m.topFeelings.count == 3, "Calm was the most named feeling (\(m.topFeelings))")
check(m.brightestMonth.map { calendar.component(.month, from: $0) } == 6, "June was the brightest month")
let few = YearReplay.calculate(blocks: blocks, checkIns: Array(moods.prefix(3)), year: 2026, now: now, calendar: calendar)
check(!few.hasMoods, "three check-ins aren't enough to sum up a year")

// When the finished year is offered
check(YearReplay.wrapUpYear(for: day(12, 3), calendar: calendar) == 2026, "December shows this year")
check(YearReplay.wrapUpYear(for: day(1, 9, year: 2027), calendar: calendar) == 2026, "early January shows last year")
check(YearReplay.wrapUpYear(for: day(1, 20, year: 2027), calendar: calendar) == nil, "later in January there's no wrap-up")
check(YearReplay.wrapUpYear(for: now, calendar: calendar) == nil, "November is the year so far")

if failures == 0 { print("Replay checks passed") } else { exit(1) }
