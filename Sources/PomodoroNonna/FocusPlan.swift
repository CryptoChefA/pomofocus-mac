import Foundation

// MARK: - Answers

/// What the questionnaire asks. Every answer has a sensible default, so a plan can be
/// built from any subset.
struct FocusPlanAnswers: Codable, Equatable, Sendable {
    enum Purpose: String, Codable, CaseIterable, Sendable { case study, work, creative, reading }
    /// How long you can stay on one thing right now before reaching for something else.
    enum Capacity: String, Codable, CaseIterable, Sendable { case underTen, tenToTwenty, twentyToThirty, overThirty }
    enum Distraction: String, Codable, CaseIterable, Sendable { case phone, socialMedia, video, games, messages, restlessThoughts }
    enum BreakHabit: String, Codable, CaseIterable, Sendable { case scroll, snack, move, mix }
    enum Energy: String, Codable, CaseIterable, Sendable { case morning, afternoon, evening, lateNight }

    var purpose: Purpose = .study
    var capacity: Capacity = .tenToTwenty
    var distractions: [Distraction] = [.phone]
    var breakHabit: BreakHabit = .scroll
    var energy: Energy = .evening
    /// Minutes a day you can realistically give this.
    var dailyMinutes = 120
    /// The block length you want to be able to hold.
    var targetMinutes = 45
    var reward = ""
}

// MARK: - Plan

/// A focus rebuild plan: a ladder of block lengths that starts where your attention is
/// today and climbs, five minutes at a time, to the length you want. Each rung is earned
/// by finishing full blocks on more than one day, so progress is real, not wishful.
struct FocusPlan: Codable, Equatable, Sendable {
    struct Level: Codable, Equatable, Sendable {
        let focusMinutes: Int
        let breakMinutes: Int
    }

    var answers: FocusPlanAnswers
    var levels: [Level]
    var levelIndex = 0
    var createdAt: Date
    var levelStartedAt: Date

    /// Full blocks at the current length needed to climb a rung…
    static let blocksPerLevel = 4
    /// …spread over at least this many days, so one heroic evening doesn't count as a habit.
    static let daysPerLevel = 2

    var level: Level { levels[min(levelIndex, levels.count - 1)] }
    var isFinalLevel: Bool { levelIndex >= levels.count - 1 }
    var longBreakMinutes: Int { min(30, max(level.breakMinutes * 2, 15)) }
    var longBreakEvery: Int { 3 }

    /// Blocks to aim for each day at the current level.
    var dailyBlocks: Int {
        let cycle = level.focusMinutes + level.breakMinutes
        return min(8, max(1, Int((Double(answers.dailyMinutes) / Double(cycle)).rounded())))
    }

    var dailyGoalMinutes: Int { dailyBlocks * level.focusMinutes }

    // MARK: Building

    static func build(from answers: FocusPlanAnswers, now: Date = Date()) -> FocusPlan {
        let start: Int = switch answers.capacity {
        case .underTen: 10
        case .tenToTwenty: 15
        case .twentyToThirty: 20
        case .overThirty: 25
        }
        let target = max(start, min(90, answers.targetMinutes))
        var minutes = Array(stride(from: start, through: target, by: 5))
        if minutes.last != target { minutes.append(target) }
        let levels = minutes.map { Level(focusMinutes: $0, breakMinutes: breakMinutes(for: $0)) }
        return FocusPlan(answers: answers, levels: levels, createdAt: now, levelStartedAt: now)
    }

    /// Breaks are about a third of the block (45 → 15), never under five minutes: long
    /// enough to actually reset, short enough not to lose the thread.
    static func breakMinutes(for focus: Int) -> Int {
        max(5, Int((Double(focus) / 3).rounded()))
    }

    // MARK: Progress

    struct Progress: Equatable, Sendable {
        let fullBlocks: Int
        let days: Int
        var isComplete: Bool { fullBlocks >= FocusPlan.blocksPerLevel && days >= FocusPlan.daysPerLevel }
        var fraction: Double {
            let blocks = Double(min(fullBlocks, FocusPlan.blocksPerLevel)) / Double(FocusPlan.blocksPerLevel)
            let spread = Double(min(days, FocusPlan.daysPerLevel)) / Double(FocusPlan.daysPerLevel)
            return min(blocks, spread)
        }
    }

    /// Full blocks at the current length since this level began, and on how many days.
    func progress(sessions: [FocusSession], calendar: Calendar = .current) -> Progress {
        let full = sessions.filter {
            $0.startedAt >= levelStartedAt && $0.outcome != .abandoned && $0.focusedSeconds >= level.focusMinutes * 60
        }
        let days = Set(full.map { calendar.startOfDay(for: $0.startedAt) })
        return Progress(fullBlocks: full.count, days: days.count)
    }

    /// Blocks finished today at (or above) the current length.
    func blocksToday(sessions: [FocusSession], now: Date = Date(), calendar: Calendar = .current) -> Int {
        sessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: now) && $0.outcome != .abandoned
                && $0.focusedSeconds >= level.focusMinutes * 60
        }.count
    }

    // MARK: Guidance

    /// House rules that follow from what pulls you away.
    var rules: [(title: String, detail: String)] {
        var rules: [(String, String)] = [
            ("Start is the whole job", "On hard days, the only goal is beginning the first block. Momentum does the rest.")
        ]
        let d = Set(answers.distractions)
        if d.contains(.phone) {
            rules.append(("Phone out of the room", "Not face down, not on silent: out of reach. Every glance costs minutes of attention."))
        }
        if d.contains(.socialMedia) || d.contains(.video) {
            rules.append(("No feeds until the reward", "Endless feeds are built to out-compete your work. Save them for after the last block."))
        }
        if d.contains(.games) {
            rules.append(("Games are the reward, not the break", "A game on a break pulls you out for good. Play after the sitting, guilt-free."))
        }
        if d.contains(.messages) {
            rules.append(("Messages wait for the long break", "Turn notifications off for the sitting and batch replies every few blocks."))
        }
        if d.contains(.restlessThoughts) {
            rules.append(("Park stray thoughts", "Keep a 'later' list beside you. Write the thought down, then go straight back."))
        }
        rules.append(("Same time, same place", "Start at \(answers.energy.window). A fixed start makes beginning automatic."))
        return rules
    }

    /// Low-stimulation breaks: they rest the mind without a spike that makes work feel dull.
    var breakMenu: [String] {
        var menu = [
            "Walk to the window and look as far away as you can",
            "Refill your water and drink a full glass",
            "Stand up and stretch your back and shoulders",
            "Step outside for a few breaths of fresh air",
            "Tidy one thing on your desk",
            "Close your eyes for a slow minute of breathing"
        ]
        switch answers.breakHabit {
        case .scroll: menu.insert("Leave the phone where it is. Walk a lap of the room instead", at: 0)
        case .snack: menu.insert("Have some fruit or a few nuts, slowly, away from the screen", at: 0)
        case .move: menu.insert("Ten squats or a quick walk around the block", at: 0)
        case .mix: break
        }
        return menu
    }

    func breakIdea(seed: Int) -> String {
        let menu = breakMenu
        return menu[abs(seed) % menu.count]
    }

    var rewardLine: String {
        let reward = answers.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        return reward.isEmpty ? "Something you enjoy, after the last block of the day" : reward
    }

    /// Rough days to reach the target if you hit the daily blocks on most days.
    var estimatedDaysToTarget: Int {
        let remaining = max(0, levels.count - 1 - levelIndex)
        let daysPerRung = max(FocusPlan.daysPerLevel, Int(ceil(Double(FocusPlan.blocksPerLevel) / Double(dailyBlocks))))
        return remaining * daysPerRung
    }
}

extension FocusPlanAnswers.Energy {
    var window: String {
        switch self {
        case .morning: "the same time each morning"
        case .afternoon: "the same time each afternoon"
        case .evening: "the same time each evening"
        case .lateNight: "the same time each night"
        }
    }
}
