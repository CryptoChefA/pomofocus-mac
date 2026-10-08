import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let now = Date(timeIntervalSince1970: 1_725_235_200)
let task = FocusTask(name: "Thesis", colorHex: "D7684D")
let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

func session(at date: Date, seconds: Int, outcome: SessionOutcome = .completed) -> FocusSession {
    FocusSession(
        taskID: task.id,
        taskName: task.name,
        intention: "Work",
        note: "",
        startedAt: date,
        endedAt: date.addingTimeInterval(TimeInterval(seconds)),
        focusedSeconds: seconds,
        pausedSeconds: 0,
        plannedSeconds: 1_500,
        outcome: outcome,
        focusRating: 4
    )
}

let result = AnalyticsSnapshot.calculate(
    sessions: [session(at: yesterday, seconds: 1_500), session(at: now, seconds: 2_700)],
    tasks: [task],
    now: now,
    calendar: calendar
)
check(result.totalFocusSeconds == 4_200, "total focus seconds")
check(result.usedDays == 2, "usage-day count")
check(result.currentStreak == 2, "current streak")
check(result.longestStreak == 2, "longest streak")
check(result.taskTotals.first?.seconds == 4_200, "lifetime task total")
check(result.taskTotals.first?.sessionCount == 2, "task session count")

let ignored = AnalyticsSnapshot.calculate(
    sessions: [session(at: now, seconds: 900, outcome: .abandoned)],
    tasks: [task],
    now: now,
    calendar: calendar
)
check(ignored.totalFocusSeconds == 0, "abandoned time is ignored")
check(ignored.usedDays == 0, "abandoned day is ignored")

let legacySettings = try JSONDecoder().decode(NonnaSettings.self, from: Data("{}".utf8))
check(legacySettings.ambientSound == .off, "older settings default ambience to off")
check(legacySettings.ambientVolume == 0.32, "older settings receive the default ambience volume")
check(legacySettings.breathingEnabled, "older settings default to the guided breathing ritual")
check(legacySettings.overtimeReminderMinutes == 1, "older settings receive the one-minute overtime reminder")

let legacyDisabledBreathing = try JSONDecoder().decode(
    NonnaSettings.self,
    from: Data("{\"breathingSeconds\":0}".utf8)
)
check(!legacyDisabledBreathing.breathingEnabled, "a disabled legacy breathing pause stays disabled")

var soundSettings = legacySettings
soundSettings.ambientSound = .rain
soundSettings.ambientVolume = 0.48
let decodedSoundSettings = try JSONDecoder().decode(
    NonnaSettings.self,
    from: JSONEncoder().encode(soundSettings)
)
check(decodedSoundSettings == soundSettings, "ambient settings survive a local JSON round trip")

var sessionWithImage = session(at: now, seconds: 1_500)
sessionWithImage.attachments = [
    SessionImageAttachment(fileName: "local-test.png", displayWidth: 312, caption: "Reference diagram")
]
let decodedSessionWithImage = try JSONDecoder().decode(
    FocusSession.self,
    from: JSONEncoder().encode(sessionWithImage)
)
check(decodedSessionWithImage == sessionWithImage, "session canvas metadata survives a JSON round trip")

let breakRecord = BreakSession(
    phase: .shortBreak,
    startedAt: now,
    endedAt: now.addingTimeInterval(420),
    restedSeconds: 420,
    pausedSeconds: 0,
    plannedSeconds: 300,
    wasSkipped: false
)
check(breakRecord.overtimeSeconds == 120, "break overtime is calculated separately")
let decodedBreakRecord = try JSONDecoder().decode(
    BreakSession.self,
    from: JSONEncoder().encode(breakRecord)
)
check(decodedBreakRecord == breakRecord, "break records survive a local JSON round trip")

let starterData = try JSONEncoder().encode(AppData.starter)
var legacyObject = try JSONSerialization.jsonObject(with: starterData) as! [String: Any]
legacyObject.removeValue(forKey: "breaks")
let legacyAppData = try JSONDecoder().decode(
    AppData.self,
    from: JSONSerialization.data(withJSONObject: legacyObject)
)
check(legacyAppData.breaks == nil, "older local databases load without break records")

check(!legacySettings.showCalendarEvents, "older settings keep the calendar overlay off")
check(legacySettings.hiddenCalendarIDs.isEmpty, "older settings hide no calendars")
check(legacySettings.overtimeAlert, "older settings turn the overtime alert on")

// Insights: 09:30–10:30 today (rated 4, 300s overtime) and 25 minutes yesterday (finished early, rated 2).
let morning = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: now)!
let insightNow = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)!
var longSession = session(at: morning, seconds: 3_600)
longSession.focusRating = 4
var earlySession = session(at: calendar.date(byAdding: .day, value: -1, to: morning)!, seconds: 1_500, outcome: .finishedEarly)
earlySession.focusRating = 2
let skippedBreak = BreakSession(
    phase: .shortBreak,
    startedAt: morning.addingTimeInterval(3_600),
    endedAt: morning.addingTimeInterval(3_660),
    restedSeconds: 60,
    pausedSeconds: 0,
    plannedSeconds: 300,
    wasSkipped: true
)
var overtimeBreak = breakRecord
overtimeBreak.startedAt = morning.addingTimeInterval(4_000)
let insights = InsightsSnapshot.calculate(
    sessions: [longSession, earlySession, session(at: morning, seconds: 900, outcome: .abandoned)],
    breaks: [skippedBreak, overtimeBreak],
    dailyGoalMinutes: 60,
    range: .week,
    now: insightNow,
    calendar: calendar
)
check(insights.dayCount == 7, "seven-day range spans seven days")
check(insights.focusSeconds == 5_100, "insights ignore abandoned sessions")
check(insights.sessionCount == 2, "insight session count")
check(insights.activeDays == 2, "insight active days")
check(insights.goalHitDays == 1, "only the one-hour day meets a one-hour goal")
check(insights.hours[9].seconds == 3_300, "half of the long session plus the early one land in the 9 o'clock hour")
check(insights.hours[10].seconds == 1_800, "the other half lands in the 10 o'clock hour")
check(insights.hours.reduce(0) { $0 + $1.seconds } == 5_100, "hourly totals add up to the focus total")
check(insights.peakHour == 9, "peak hour")
check(insights.averageRating == 3, "average rating")
check(insights.hours[9].averageRating == 3, "rating by start hour")
check(insights.completionRate == 0.5, "completion rate")
check(insights.skippedBreakCount == 1, "skipped break count")
check(insights.breakSeconds == 480, "break seconds")
check(insights.averageBreakOvertimeSeconds == 120, "break overtime averages finished breaks only")
check(insights.averageFocusOvertimeSeconds == 2_100, "focus overtime per completed session")
check(insights.overtimeTrend.count == 1 && !insights.overtimeTrendIsWeekly, "short ranges bucket overtime by day")
check(insights.weekdays.count == 7 && insights.months.count == 6, "weekday and month series are complete")

let deepDive = DeepDiveSnapshot.calculate(
    sessions: [longSession, earlySession, session(at: morning, seconds: 900, outcome: .abandoned)],
    breaks: [skippedBreak, overtimeBreak],
    tasks: [task],
    dailyGoalMinutes: 60,
    range: .week,
    now: insightNow,
    calendar: calendar
)
check(deepDive.days.count == 7, "deep dive creates one point per range day")
check(deepDive.totalFocusSeconds == 5_100, "deep dive focus total")
check(deepDive.medianSessionSeconds == 2_550, "deep dive median session")
check(deepDive.completedCount == 1 && deepDive.earlyCount == 1 && deepDive.abandonedCount == 1, "deep dive outcome counts")
check(deepDive.totalBreakOvertimeSeconds == 120, "deep dive break overtime")
check(deepDive.skippedBreakCount == 1 && deepDive.breakOvertimeCount == 1, "deep dive break outcomes")
check(deepDive.deepSessionCount == 1, "deep dive identifies 50-minute blocks")
check(deepDive.tasks.first?.seconds == 5_100, "deep dive task allocation")
check((0...100).contains(deepDive.consistencyScore), "deep dive consistency score is bounded")

let emptyInsights = InsightsSnapshot.calculate(sessions: [], breaks: [], dailyGoalMinutes: 120, range: .all, now: insightNow, calendar: calendar)
check(emptyInsights.sessionCount == 0 && emptyInsights.dayCount == 1, "empty insights are safe")
check(emptyInsights.peakHour == nil && emptyInsights.weekChange == nil, "empty insights have no peaks")

let emptyDeepDive = DeepDiveSnapshot.calculate(
    sessions: [], breaks: [], tasks: [], dailyGoalMinutes: 120,
    range: .month, now: insightNow, calendar: calendar
)
check(emptyDeepDive.days.count == 30 && emptyDeepDive.totalFocusSeconds == 0, "empty deep dive is safe")

print("Analytics and settings checks passed")
