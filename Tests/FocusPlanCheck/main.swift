import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let start = Date(timeIntervalSince1970: 1_790_000_000)

// A struggling starter aiming for 45/15.
var answers = FocusPlanAnswers()
answers.capacity = .underTen
answers.targetMinutes = 45
answers.dailyMinutes = 60
answers.distractions = [.phone, .video]
var plan = FocusPlan.build(from: answers, now: start)

check(plan.levels.map(\.focusMinutes) == [10, 15, 20, 25, 30, 35, 40, 45], "ladder climbs 10 → 45 in fives")
check(plan.levels.last?.breakMinutes == 15, "45-minute blocks get 15-minute breaks")
check(plan.levels.first?.breakMinutes == 5, "breaks never drop under five minutes")
check(plan.dailyBlocks == 4, "an hour a day at 10/5 is four blocks")
check(plan.rules.contains { $0.title == "Phone out of the room" }, "phone distraction adds the phone rule")
check(plan.rules.contains { $0.title == "No feeds until the reward" }, "video distraction adds the feeds rule")
check(!plan.isFinalLevel, "a new plan starts at the bottom")

func session(day: Int, minutes: Int, outcome: SessionOutcome = .completed) -> FocusSession {
    let begin = start.addingTimeInterval(TimeInterval(day * 86_400 + 3_600))
    return FocusSession(taskID: nil, taskName: "Study", intention: "", note: "", startedAt: begin,
                        endedAt: begin.addingTimeInterval(TimeInterval(minutes * 60)), focusedSeconds: minutes * 60,
                        pausedSeconds: 0, plannedSeconds: 600, outcome: outcome, focusRating: nil)
}

// Four full blocks on one day: not enough spread.
let oneDay = (0..<4).map { _ in session(day: 0, minutes: 10) }
check(!plan.progress(sessions: oneDay, calendar: calendar).isComplete, "four blocks on one day do not level up")
// Short or abandoned blocks never count.
let weak = [session(day: 0, minutes: 8), session(day: 1, minutes: 9), session(day: 1, minutes: 12, outcome: .abandoned)]
check(plan.progress(sessions: weak, calendar: calendar).fullBlocks == 0, "short and abandoned blocks do not count")
// Two days, four full blocks: earned.
let earned = [session(day: 0, minutes: 10), session(day: 0, minutes: 11), session(day: 1, minutes: 10), session(day: 1, minutes: 14)]
let progress = plan.progress(sessions: earned, calendar: calendar)
check(progress.isComplete && progress.fraction == 1, "four full blocks over two days level up")

// Climbing all the way.
plan.levelIndex = plan.levels.count - 1
check(plan.isFinalLevel && plan.level.focusMinutes == 45, "the last rung is the target")
check(plan.estimatedDaysToTarget == 0, "nothing left to climb at the top")

// Already strong: the target is the start.
var strong = FocusPlanAnswers()
strong.capacity = .overThirty
strong.targetMinutes = 25
let strongPlan = FocusPlan.build(from: strong, now: start)
check(strongPlan.levels.count == 1 && strongPlan.isFinalLevel, "a target at or below today's capacity is a single rung")

// Odd target still lands exactly.
var odd = FocusPlanAnswers()
odd.capacity = .tenToTwenty
odd.targetMinutes = 90
check(FocusPlan.build(from: odd).levels.last?.focusMinutes == 90 && FocusPlan.build(from: odd).levels.last?.breakMinutes == 30, "90-minute target ends at 90/30")

print("Focus plan checks passed")
