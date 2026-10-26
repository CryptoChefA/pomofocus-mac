import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!
let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!

/// A block starting `minutesIn` after 9am, with `pauses` evenly spread pauses of 2 minutes.
func block(_ minutesIn: Int, focused: Int, planned: Int = 25, outcome: SessionOutcome = .completed, pauses: Int = 0) -> FocusSession {
    let start = day.addingTimeInterval(TimeInterval(minutesIn * 60))
    var intervals: [ActivityInterval] = []
    var cursor = start
    let piece = TimeInterval(focused * 60) / TimeInterval(pauses + 1)
    for index in 0...pauses {
        intervals.append(ActivityInterval(startedAt: cursor, endedAt: cursor.addingTimeInterval(piece)))
        cursor = cursor.addingTimeInterval(piece + (index < pauses ? 120 : 0))
    }
    return FocusSession(taskID: nil, taskName: "Study", intention: "", note: "", startedAt: start, endedAt: cursor,
                        focusedSeconds: focused * 60, pausedSeconds: pauses * 120, plannedSeconds: planned * 60,
                        outcome: outcome, focusRating: nil, activeIntervals: intervals)
}

func rest(_ minutesIn: Int, rested: Int, planned: Int = 5, skipped: Bool = false) -> BreakSession {
    let start = day.addingTimeInterval(TimeInterval(minutesIn * 60))
    let end = start.addingTimeInterval(TimeInterval(rested * 60))
    return BreakSession(phase: .shortBreak, startedAt: start, endedAt: end, restedSeconds: rested * 60, pausedSeconds: 0,
                        plannedSeconds: planned * 60, wasSkipped: skipped, activeIntervals: [ActivityInterval(startedAt: start, endedAt: end)])
}

func score(_ sessions: [FocusSession], _ breaks: [BreakSession] = [], goal: Int = 100) -> FocusScore? {
    FocusScore.compute(day: day, sessions: sessions, breaks: breaks, goalMinutes: goal, calendar: calendar)
}

// Nothing started, no score.
check(score([]) == nil, "no blocks, no score")

// A model day: four full blocks, no pauses, breaks on time, goal met.
let perfect = score([block(0, focused: 25), block(30, focused: 25), block(60, focused: 25), block(90, focused: 25)],
                    [rest(25, rested: 5), rest(55, rested: 5), rest(85, rested: 5)])!
check(perfect.total == 100, "perfect day scores 100 (\(perfect.total))")
check(perfect.label == "Locked in", "perfect label")
check(perfect.parts.count == 5 && perfect.parts.reduce(0, { $0 + $1.maxPoints }) == 100, "parts add up to 100")

// A messy day: one block abandoned, lots of pauses, a long break, under goal.
let messy = score([block(0, focused: 10, outcome: .abandoned, pauses: 3), block(40, focused: 20, outcome: .finishedEarly, pauses: 4)],
                  [rest(15, rested: 25)])!
check(messy.total < 40, "messy day scores low (\(messy.total))")
check(messy.parts.first { $0.kind == .followThrough }!.detail == "0 of 2 blocks finished", "follow-through detail")
check(messy.parts.first { $0.kind == .breaks }!.detail.contains("ran long"), "long break is called out")
check(messy.weakest != nil, "there's always something to work on")

// A runaway timer doesn't inflate the score: 10 hours of "focus" counts as 25 + 15 minutes.
let runaway = score([block(0, focused: 600)], goal: 600)!
let timePart = runaway.parts.first { $0.kind == .time }!
check(timePart.detail.hasPrefix("40m of"), "runaway overtime is capped (\(timePart.detail))")

// One block: breaks aren't expected yet.
let single = score([block(0, focused: 25)])!
check(single.parts.first { $0.kind == .breaks }!.points == 10, "single block gets full break credit")

// Another day doesn't leak in.
let tomorrow = block(24 * 60, focused: 25)
check(score([tomorrow]) == nil, "only that day's blocks count")

// History: oldest first, nil for empty days.
let history = FocusScore.history(days: 3, endingOn: day.addingTimeInterval(86_400), sessions: [block(0, focused: 25)], breaks: [], goalMinutes: 100, calendar: calendar)
check(history.count == 3 && history[1].score != nil && history[0].score == nil && history[2].score == nil, "history lines up by day")

// Runaway detection and trimming.
let forgotten = block(0, focused: 25 + 600)
check(RunawayTimers.isRunaway(forgotten), "10h over is a runaway")
check(!RunawayTimers.isRunaway(block(0, focused: 40)), "15m over is not")
let fixed = RunawayTimers.trimmed(forgotten)
check(fixed.focusedSeconds == 25 * 60, "trimmed to planned")
check(abs(fixed.endedAt.timeIntervalSince(fixed.startedAt) - 25 * 60) < 1, "end moves back (\(fixed.endedAt.timeIntervalSince(fixed.startedAt)))")
check(fixed.activeIntervals?.count == 1, "intervals cut")

// Ten minutes of focus, a two-minute pause, then the timer runs for ten hours.
var pausedForgotten = block(0, focused: 25 + 600)
pausedForgotten.activeIntervals = [
    ActivityInterval(startedAt: day, endedAt: day.addingTimeInterval(600)),
    ActivityInterval(startedAt: day.addingTimeInterval(720), endedAt: day.addingTimeInterval(720 + 615 * 60)),
]
let pausedFixed = RunawayTimers.trimmed(pausedForgotten)
let active = pausedFixed.activeIntervals!.reduce(0.0) { $0 + $1.duration() }
check(abs(active - 25 * 60) < 1 && pausedFixed.pausedSeconds == 120, "pauses before the cut are kept (\(active), \(pausedFixed.pausedSeconds))")

let longBreak = rest(0, rested: 5 + 600)
check(RunawayTimers.isRunaway(longBreak), "10h break is a runaway")
let fixedBreak = RunawayTimers.trimmed(longBreak)
check(fixedBreak.restedSeconds == 300 && fixedBreak.overtimeSeconds == 0, "break trimmed")

print("Focus score checks passed")
