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

// Finishing too few blocks blocks the climb, even with enough full ones.
var spotty = FocusPlan.build(from: answers, now: start)
let spottySessions = earned + (0..<3).map { _ in session(day: 1, minutes: 4, outcome: .finishedEarly) }
check(!spotty.progress(sessions: spottySessions, calendar: calendar).isComplete, "4 of 7 finished (57%) is below the 70% bar")

// Repeatedly failing a level steps back one.
spotty.levelIndex = 3
let struggling = (0..<6).map { i in session(day: i % 2, minutes: i == 0 ? 25 : 9) }
func plannedAt(_ s: FocusSession, _ minutes: Int) -> FocusSession { var s = s; s.plannedSeconds = minutes * 60; return s }
let atLevel = struggling.map { plannedAt($0, 25) }
check(spotty.adjustment(sessions: atLevel, calendar: calendar) == .stepBack, "1 of 6 finished at 25 min steps back")
spotty.levelIndex = 0
check(spotty.adjustment(sessions: atLevel.map { plannedAt($0, 10) }, calendar: calendar) != .stepBack, "never steps below the first level")

// Phases.
let fresh = FocusPlan.build(from: answers, now: start)
check(fresh.phase(now: start.addingTimeInterval(3 * 86_400), calendar: calendar).phase == .reset, "first week is Reset")
check(fresh.phase(now: start.addingTimeInterval(10 * 86_400), calendar: calendar).phase == .build, "then Build")
var nearTop = fresh; nearTop.levelIndex = 6
check(nearTop.phase(now: start.addingTimeInterval(20 * 86_400), calendar: calendar).phase == .extend, "upper rungs are Extend")
var top = fresh; top.levelIndex = top.levels.count - 1
check(top.phase(now: start.addingTimeInterval(20 * 86_400), calendar: calendar).phase == .sustain, "target reached is Sustain")

// Metrics.
let m = FocusMetrics.measure(sessions: earned + [session(day: 1, minutes: 4, outcome: .abandoned)],
                             from: start, to: start.addingTimeInterval(7 * 86_400), calendar: calendar)
check(m.blocks == 5 && m.activeDays == 2, "metrics count blocks and days")
check(abs((m.completionRate ?? 0) - 0.8) < 0.001, "4 of 5 blocks finished is 80%")
check(m.startSpreadMinutes == 0, "same start time every day has no spread")

// Every piece of advice is sourced, and every source exists.
let everything = top.rules + top.breakMenu + [top.reward, FocusPlan.ladderGuidance, FocusPlan.breakGuidance]
var allAnswers = answers; allAnswers.distractions = FocusPlanAnswers.Distraction.allCases
let allRules = FocusPlan.build(from: allAnswers).rules
check((everything + allRules).allSatisfy { !$0.sources.isEmpty }, "every rule, break idea and explanation cites a source")
check(Citation.ID.allCases.allSatisfy { FocusScience.library[$0] != nil }, "every citation id resolves")
check(FocusScience.all.allSatisfy { $0.scholarURL != nil && $0.year > 1900 && !$0.finding.isEmpty }, "citations are complete")

// Coming back after time away: warm-ups, not a failed full-length block.
var climbed = FocusPlan.build(from: answers, now: start)
climbed.levelIndex = 5 // 35-minute blocks
func at(_ day: Int) -> Date { start.addingTimeInterval(TimeInterval(day * 86_400 + 7_200)) }
let beforeBreak = [session(day: 0, minutes: 35), session(day: 1, minutes: 35)]
check(climbed.reentry(sessions: beforeBreak, now: at(3), calendar: calendar) == nil, "one day off is not a break")
let back = climbed.reentry(sessions: beforeBreak, now: at(6), calendar: calendar)
check(back?.daysAway == 4 && back?.warmupMinutes == 30 && back?.blocksLeft == 1, "four days away: one 30-minute warm-up")
let longBack = climbed.reentry(sessions: beforeBreak, now: at(12), calendar: calendar)
check(longBack?.warmupMinutes == 25 && longBack?.blocksLeft == 2, "ten days away: two 25-minute warm-ups")
let warmedUp = beforeBreak + [session(day: 6, minutes: 30)]
check(climbed.reentry(sessions: warmedUp, now: at(6).addingTimeInterval(3_600), calendar: calendar) == nil, "after the warm-up, full blocks return")
check(climbed.todayTarget(sessions: beforeBreak, now: at(6), calendar: calendar) == 1, "the first day back asks for one block")

// Never miss twice.
check(climbed.missedYesterday(sessions: beforeBreak, now: at(3), calendar: calendar), "a gap yesterday is noticed")
check(climbed.todayTarget(sessions: beforeBreak, now: at(3), calendar: calendar) == 1, "after a missed day, one block is the goal")

// Struggling is judged on recent blocks, not an early good run.
var stuck = climbed
stuck.levelStartedAt = start
let early = (0..<6).map { _ in session(day: 0, minutes: 35) }.map { s -> FocusSession in var s = s; s.plannedSeconds = 35 * 60; return s }
let slump = (0..<6).map { i -> FocusSession in var s = session(day: 2 + i / 3, minutes: 8, outcome: .finishedEarly); s.plannedSeconds = 35 * 60; return s }
check(stuck.progress(sessions: early + slump, calendar: calendar).isStruggling, "a recent slump steps back even after a strong start")

// A block split across two lists still counts as one full block toward the plan.
func split(day: Int, first: Int, second: Int) -> [FocusSession] {
    let block = UUID()
    var a = session(day: day, minutes: first); a.plannedSeconds = first * 60; a.blockID = block
    var b = session(day: day, minutes: second); b.plannedSeconds = second * 60; b.blockID = block
    b.startedAt = a.endedAt; b.endedAt = b.startedAt.addingTimeInterval(TimeInterval(second * 60))
    return [a, b]
}
let splitPlan = FocusPlan.build(from: answers, now: start)
let splitBlocks = split(day: 0, first: 6, second: 4) + split(day: 0, first: 5, second: 5)
    + split(day: 1, first: 7, second: 3) + split(day: 1, first: 2, second: 8)
let splitProgress = splitPlan.progress(sessions: splitBlocks, calendar: calendar)
check(splitProgress.attempts == 4 && splitProgress.fullBlocks == 4, "split blocks count once, at full length")
check(FocusSession.mergedBlocks(splitBlocks).count == 4, "parts merge back into blocks")

// Simple tasks is on for data saved before it existed, and a choice to turn it off sticks.
let oldSettings = try! JSONDecoder().decode(NonnaSettings.self, from: Data("{}".utf8))
check(oldSettings.simpleTasks, "simple tasks defaults on for older data")
var detailed = NonnaSettings()
detailed.simpleTasks = false
let roundTrip = try! JSONDecoder().decode(NonnaSettings.self, from: try! JSONEncoder().encode(detailed))
check(!roundTrip.simpleTasks, "turning simple tasks off is saved")

print("Focus plan checks passed")
