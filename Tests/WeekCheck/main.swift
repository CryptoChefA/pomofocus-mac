import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); failures += 1 }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
calendar.firstWeekday = 2   // weeks start on Monday
let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))!
func at(_ dayOffset: Int, _ hour: Int) -> Date { calendar.date(byAdding: .hour, value: dayOffset * 24 + hour, to: monday)! }
typealias B = WeekSummary.Block

check(WeekSummary.weekStart(containing: at(3, 15), calendar: calendar) == monday, "week starts on the calendar's first weekday")

// Nothing at all
let empty = WeekSummary.calculate(blocks: [], checkIns: [], weekStart: monday, calendar: calendar)
check(!empty.hasFocus && empty.days.count == 7 && empty.bestDay == nil, "an empty week")
check(empty.suggestion.contains("quiet week"), "a kind line for an empty week")

// A morning-heavy week across four days
var blocks: [B] = [
    B(start: at(0, 9), seconds: 1500, list: "Calculus"), B(start: at(0, 10), seconds: 1500, list: "Calculus"),
    B(start: at(1, 8), seconds: 1500, list: "Chemistry"), B(start: at(2, 9), seconds: 1500, list: "Calculus"),
    B(start: at(3, 19), seconds: 1200, list: "Essay"),
    B(start: at(-3, 9), seconds: 1500, list: "Calculus"),   // the week before
    B(start: at(8, 9), seconds: 1500, list: "Calculus"),    // the week after
]
let s = WeekSummary.calculate(blocks: blocks, checkIns: [], weekStart: monday, calendar: calendar)
check(s.totalSeconds == 7200 && s.blockCount == 5, "only this week's blocks count (\(s.totalSeconds))")
check(s.previousSeconds == 1500, "the week before is compared")
check(s.daysFocused == 4, "four days with focus")
check(s.bestDay?.seconds == 3000 && calendar.isDate(s.bestDay!.day, inSameDayAs: monday), "Monday was the best day")
check(s.bestTime == .morning && abs(s.bestTimeShare - 6000.0 / 7200) < 0.001, "mornings had most of the focus")
check(s.topList?.name == "Calculus" && s.topList?.seconds == 4500, "Calculus was the top list")
check(s.suggestion.contains("morning"), "suggests protecting the morning (\(s.suggestion))")

// Heavy moods come first, gently
let heavy = (0..<3).map { MoodCheckIn(date: at($0, 20), level: 2) }
let h = WeekSummary.calculate(blocks: blocks, checkIns: heavy, weekStart: monday, calendar: calendar)
check(h.moodCheckIns == 3 && h.moodAverage == 2 && h.suggestion.contains("heavier week"), "a heavy week gets the kind suggestion")

// Few days, no strong time of day
let few = WeekSummary.calculate(blocks: [B(start: at(4, 14), seconds: 1500, list: nil)], checkIns: [], weekStart: monday, calendar: calendar)
check(few.suggestion.contains("one day"), "one day of focus")
check(few.topList == nil, "no list means no top list")

// Clearly up on the week before, spread across the day
let spread = (0..<6).map { B(start: at($0, [9, 14, 20][$0 % 3]), seconds: 1500, list: "Reading") } + [B(start: at(-2, 9), seconds: 3000, list: nil)]
let u = WeekSummary.calculate(blocks: spread, checkIns: [], weekStart: monday, calendar: calendar)
check(u.suggestion.contains("more than the week before"), "a week up on the last (\(u.suggestion))")

if failures == 0 { print("Week checks passed") } else { exit(1) }
