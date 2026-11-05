import Foundation

var failures = 0
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL: \(message)"); failures += 1 }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Vancouver")!
let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 15))!
func day(_ back: Int, hour: Int = 9) -> Date {
    let start = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now))!
    return calendar.date(byAdding: .hour, value: hour, to: start)!
}

// Scale words
check(MoodScale.title(1) == "Very unpleasant" && MoodScale.title(4) == "Neutral" && MoodScale.title(7) == "Very pleasant", "scale titles")
check(MoodScale.title(0) == "Very unpleasant" && MoodScale.title(9) == "Very pleasant", "titles clamp out-of-range levels")
check(MoodScale.feelings(for: 2).contains("Stressed") && MoodScale.feelings(for: 6).contains("Grateful"), "feelings follow the scale")
check(MoodScale.feelings(near: 0.5).count == 12 && MoodScale.feelings(near: 0.5).contains("Okay"), "twelve words around neutral")
let near = MoodScale.feelings(near: 0.9).compactMap(MoodScale.valence(ofFeeling:))
check(near == near.sorted() && near.allSatisfy { $0 > 0.6 }, "words near very pleasant are pleasant and in order")
check(MoodScale.level(forValence: 0) == 1 && MoodScale.level(forValence: 0.5) == 4 && MoodScale.level(forValence: 1) == 7 && MoodScale.level(forValence: 0.93) == 7, "slider position to level")
check(Set(MoodScale.vocabulary.map(\.word)).count == MoodScale.vocabulary.count, "no repeated words")
let oldFile = #"[{"id":"6F1C9D2E-1111-4A2B-9C3D-000000000001","date":"2026-11-01T09:00:00Z","level":5,"feelings":["Calm"],"influences":[]}]"#
let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
let decodedOld = try? decoder.decode([MoodCheckIn].self, from: Data(oldFile.utf8))
check(decodedOld?.first?.level == 5 && decodedOld?.first?.valence == nil && decodedOld?.first?.note == nil, "check-ins saved before valence and notes still load")

// Nothing yet
let empty = MoodSummary.calculate(checkIns: [], focusByDay: [:], now: now, calendar: calendar)
check(empty.days.count == 30 && empty.days.allSatisfy { $0.level == nil }, "30 empty days with no check-ins")
check(empty.averageLevel == nil && !empty.heavyStretch && empty.focusOnGoodDays == nil, "no averages from nothing")

// The latest check-in of a day wins; the window is oldest first and ends today
let sameDay = [MoodCheckIn(date: day(0, hour: 8), level: 2), MoodCheckIn(date: day(0, hour: 20), level: 6)]
let s1 = MoodSummary.calculate(checkIns: sameDay, focusByDay: [:], now: now, calendar: calendar)
check(s1.days.last?.level == 6 && s1.checkInsInWindow == 1, "one check-in per day, the latest wins")
check(calendar.isDate(s1.days.last!.day, inSameDayAs: now) && s1.days.first!.day < s1.days.last!.day, "window ends today")

// Older than the window is left out
let old = MoodSummary.calculate(checkIns: [MoodCheckIn(date: day(40), level: 1)], focusByDay: [:], now: now, calendar: calendar)
check(old.checkInsInWindow == 0, "check-ins older than 30 days are outside the window")

// Top feelings and influences
let tagged = [
    MoodCheckIn(date: day(1), level: 2, feelings: ["Stressed", "Tired"], influences: ["Exams", "Sleep"]),
    MoodCheckIn(date: day(2), level: 3, feelings: ["Stressed"], influences: ["Exams"]),
    MoodCheckIn(date: day(3), level: 6, feelings: ["Happy"], influences: ["Friends"]),
]
let s2 = MoodSummary.calculate(checkIns: tagged, focusByDay: [:], now: now, calendar: calendar)
check(s2.topFeelings.first?.name == "Stressed" && s2.topFeelings.first?.count == 2, "most common feeling first")
check(s2.topInfluences.first?.name == "Exams" && abs(s2.topInfluences.first!.averageLevel - 2.5) < 0.001, "influence keeps its average mood")
check(abs(s2.averageLevel! - 11.0 / 3) < 0.001, "average level")

// Focus on good and hard days only once there are three of each
var focus: [Date: Int] = [:]
var mixed: [MoodCheckIn] = []
for back in 1...3 { mixed.append(MoodCheckIn(date: day(back), level: 6)); focus[calendar.startOfDay(for: day(back))] = 3600 }
for back in 4...5 { mixed.append(MoodCheckIn(date: day(back), level: 2)); focus[calendar.startOfDay(for: day(back))] = 1200 }
check(MoodSummary.calculate(checkIns: mixed, focusByDay: focus, now: now, calendar: calendar).focusOnGoodDays == nil, "no comparison with only two hard days")
mixed.append(MoodCheckIn(date: day(6), level: 1))
let s3 = MoodSummary.calculate(checkIns: mixed, focusByDay: focus, now: now, calendar: calendar)
check(s3.focusOnGoodDays == 3600 && s3.focusOnHardDays == 800, "good-day and hard-day focus averages (no focus counts as zero)")

// A heavy fortnight: five or more check-ins, at least 70% unpleasant
let heavy = (1...6).map { MoodCheckIn(date: day($0), level: $0 == 6 ? 5 : 2) }
check(MoodSummary.calculate(checkIns: heavy, focusByDay: [:], now: now, calendar: calendar).heavyStretch, "mostly unpleasant fortnight is noticed")
let fewer = (1...4).map { MoodCheckIn(date: day($0), level: 1) }
check(!MoodSummary.calculate(checkIns: fewer, focusByDay: [:], now: now, calendar: calendar).heavyStretch, "four check-ins are too few to call it")
let balanced = (1...6).map { MoodCheckIn(date: day($0), level: $0 % 2 == 0 ? 2 : 6) }
check(!MoodSummary.calculate(checkIns: balanced, focusByDay: [:], now: now, calendar: calendar).heavyStretch, "a mixed fortnight isn't heavy")

// Round trip, and old data files without check-ins still decode
let encoded = try! JSONEncoder().encode(tagged)
check(try! JSONDecoder().decode([MoodCheckIn].self, from: encoded) == tagged, "check-ins round-trip through JSON")

if failures == 0 { print("Mood checks passed") } else { exit(1) }
