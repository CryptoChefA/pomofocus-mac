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

/// One piece of advice and the research behind it.
struct PlanGuidance: Equatable, Sendable {
    let title: String
    let detail: String
    let sources: [Citation.ID]
}

// MARK: - Plan

/// A focus rebuild plan, built on the research in `FocusScience`.
///
/// It starts a little below the attention span you have today, so the first blocks are
/// wins (mastery experiences build self-efficacy), and climbs in five-minute proximal
/// steps to the block length you want. A step is earned on evidence, not on a calendar:
/// enough full blocks, on more than one day, at a good completion rate. If a length keeps
/// beating you, the plan steps back one level to consolidate.
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
    /// …spread over at least this many days, so one heroic evening doesn't count as a habit…
    static let daysPerLevel = 2
    /// …with at least this share of started blocks finished at full length.
    static let levelUpCompletion = 0.7
    /// Below this completion rate over enough attempts, the plan steps back a level.
    static let stepBackCompletion = 0.4
    static let stepBackAttempts = 5
    /// Lally et al. (2010): median days for a repeated behaviour to become automatic.
    static let habitDays = 66

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

    /// Breaks are about a third of the block (45 → 15), never under five minutes. Sustained
    /// attention is effortful and declines without rest (Warm et al., 2008), and breaks
    /// restore vigour (Albulescu et al., 2022).
    static func breakMinutes(for focus: Int) -> Int {
        max(5, Int((Double(focus) / 3).rounded()))
    }

    // MARK: Progress

    struct Progress: Equatable, Sendable {
        /// Blocks started at this level, including ones that were abandoned or cut short.
        let attempts: Int
        let fullBlocks: Int
        let days: Int

        var completionRate: Double { attempts == 0 ? 0 : Double(fullBlocks) / Double(attempts) }

        var isComplete: Bool {
            fullBlocks >= FocusPlan.blocksPerLevel && days >= FocusPlan.daysPerLevel
                && completionRate >= FocusPlan.levelUpCompletion
        }

        var isStruggling: Bool {
            attempts >= FocusPlan.stepBackAttempts && completionRate < FocusPlan.stepBackCompletion
        }

        var fraction: Double {
            let blocks = Double(min(fullBlocks, FocusPlan.blocksPerLevel)) / Double(FocusPlan.blocksPerLevel)
            let spread = Double(min(days, FocusPlan.daysPerLevel)) / Double(FocusPlan.daysPerLevel)
            let quality = attempts == 0 ? 0 : min(1, completionRate / FocusPlan.levelUpCompletion)
            return min(blocks, spread, quality)
        }
    }

    /// Blocks started at the current length since this level began.
    func progress(sessions: [FocusSession], calendar: Calendar = .current) -> Progress {
        let minutes = level.focusMinutes
        let started = sessions.filter {
            $0.startedAt >= levelStartedAt && $0.plannedSeconds >= minutes * 60 - 30 && $0.plannedSeconds > 0
        }
        let full = started.filter { $0.outcome != .abandoned && $0.focusedSeconds >= minutes * 60 }
        let days = Set(full.map { calendar.startOfDay(for: $0.startedAt) })
        return Progress(attempts: started.count, fullBlocks: full.count, days: days.count)
    }

    enum Adjustment: Equatable, Sendable { case levelUp, stepBack }

    /// What the evidence says to do next, if anything.
    func adjustment(sessions: [FocusSession], calendar: Calendar = .current) -> Adjustment? {
        let progress = progress(sessions: sessions, calendar: calendar)
        if !isFinalLevel, progress.isComplete { return .levelUp }
        if levelIndex > 0, progress.isStruggling { return .stepBack }
        return nil
    }

    /// Blocks finished today at (or above) the current length.
    func blocksToday(sessions: [FocusSession], now: Date = Date(), calendar: Calendar = .current) -> Int {
        sessions.filter {
            calendar.isDate($0.startedAt, inSameDayAs: now) && $0.outcome != .abandoned
                && $0.focusedSeconds >= level.focusMinutes * 60
        }.count
    }

    /// Rough days to reach the target if you hit the daily blocks on most days.
    var estimatedDaysToTarget: Int {
        let remaining = max(0, levels.count - 1 - levelIndex)
        let daysPerRung = max(FocusPlan.daysPerLevel, Int(ceil(Double(FocusPlan.blocksPerLevel) / Double(dailyBlocks))))
        return remaining * daysPerRung
    }

    // MARK: Phases

    enum Phase: String, Sendable {
        case reset, build, extend, sustain
    }

    struct PhaseInfo: Sendable {
        let phase: Phase
        let title: String
        let focus: String
        let sources: [Citation.ID]
    }

    func daysSinceStart(now: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: createdAt), to: calendar.startOfDay(for: now)).day ?? 0
    }

    func phase(now: Date = Date(), calendar: Calendar = .current) -> PhaseInfo {
        let day = daysSinceStart(now: now, calendar: calendar)
        if isFinalLevel {
            let left = max(0, FocusPlan.habitDays - day)
            return PhaseInfo(
                phase: .sustain, title: "Sustain",
                focus: left > 0
                    ? "You've reached your target. Keep the same time and place: around \(left) more days of repetition and starting becomes automatic."
                    : "Your focus routine has had time to become a habit. Keep it light and regular, and missing a day won't undo it.",
                sources: [.habitFormation, .implementationIntentions])
        }
        if day < 7 {
            return PhaseInfo(
                phase: .reset, title: "Reset",
                focus: "Week one is about starting, not stamina. Begin at the same time each day, take the phone out of the room, and let short blocks feel easy.",
                sources: [.implementationIntentions, .phonePresence, .selfEfficacy])
        }
        if Double(levelIndex) >= Double(levels.count - 1) * 0.6 {
            return PhaseInfo(
                phase: .extend, title: "Extend",
                focus: "Your blocks are getting long. Protect your breaks: step away from screens, get outside or move, so the next block starts fresh.",
                sources: [.vigilanceWork, .natureAttention, .exerciseCognition])
        }
        return PhaseInfo(
            phase: .build, title: "Build",
            focus: "Climb one five-minute step at a time. Finish blocks at full length on different days, and the plan moves you up when your numbers show you're ready.",
            sources: [.proximalGoals, .goalSetting, .progressMonitoring])
    }

    // MARK: Guidance

    /// House rules that follow from what pulls you away.
    var rules: [PlanGuidance] {
        var rules = [
            PlanGuidance(title: "Start is the whole job",
                         detail: "On hard days, the only goal is beginning one block. Small wins build the belief that you can do the next one.",
                         sources: [.selfEfficacy, .proximalGoals])
        ]
        let d = Set(answers.distractions)
        if d.contains(.phone) {
            rules.append(PlanGuidance(title: "Phone out of the room",
                                      detail: "Not face down, not on silent: in another room. Its mere presence measurably lowers working memory.",
                                      sources: [.phonePresence, .notificationCost]))
        }
        if d.contains(.socialMedia) || d.contains(.video) {
            rules.append(PlanGuidance(title: "No feeds until the reward",
                                      detail: "Short-form feeds impair your ability to hold onto what you meant to do, and leave attention residue behind.",
                                      sources: [.shortFormVideo, .attentionResidue]))
        }
        if d.contains(.games) {
            rules.append(PlanGuidance(title: "Games are the reward, not the break",
                                      detail: "Play after the last block. An enjoyable activity reinforces the work it follows.",
                                      sources: [.premackPrinciple]))
        }
        if d.contains(.messages) {
            rules.append(PlanGuidance(title: "Messages wait for the long break",
                                      detail: "Notifications off for the sitting; batch replies. Each switch costs attention and adds stress.",
                                      sources: [.notificationCost, .interruptionCost, .attentionResidue]))
        }
        if d.contains(.restlessThoughts) {
            rules.append(PlanGuidance(title: "Park stray thoughts",
                                      detail: "Keep a 'later' list beside you. Writing a concrete plan for a nagging task stops it intruding.",
                                      sources: [.planMaking, .mindWandering]))
        }
        rules.append(PlanGuidance(title: "Same time, same place",
                                  detail: "Start at \(answers.energy.window). A fixed when-and-where makes starting far more likely, and repeating it builds the habit.",
                                  sources: [.implementationIntentions, .habitFormation, .circadianCognition]))
        rules.append(PlanGuidance(title: "Let the numbers decide",
                                  detail: "Pomofocus records every block. Watching your own progress is one of the most reliable ways to reach a goal.",
                                  sources: [.progressMonitoring]))
        return rules
    }

    /// Low-stimulation breaks: they let directed attention recover instead of spending it.
    var breakMenu: [PlanGuidance] {
        var menu = [
            PlanGuidance(title: "Look out of a window, as far away as you can", detail: "Natural views let attention recover.",
                         sources: [.restorationTheory, .natureAttention]),
            PlanGuidance(title: "Step outside for a few minutes", detail: "Time outdoors improves directed attention afterwards.",
                         sources: [.natureAttention]),
            PlanGuidance(title: "Walk to another room and back", detail: "Even brief movement supports attention.",
                         sources: [.exerciseCognition, .microBreaks]),
            PlanGuidance(title: "Stand up and stretch your back and shoulders", detail: "Physical micro-breaks reduce fatigue.",
                         sources: [.microBreaks]),
            PlanGuidance(title: "Refill your water and drink a full glass", detail: "A real pause away from the screen.",
                         sources: [.microBreaks]),
            PlanGuidance(title: "A minute of slow belly breathing", detail: "Slow breathing practice improves sustained attention.",
                         sources: [.diaphragmaticBreathing]),
        ]
        switch answers.breakHabit {
        case .scroll:
            menu.insert(PlanGuidance(title: "Leave the phone where it is. Walk a lap of the room instead",
                                     detail: "Feeds on a break carry over into the next block.",
                                     sources: [.shortFormVideo, .exerciseCognition]), at: 0)
        case .snack:
            menu.insert(PlanGuidance(title: "Have some fruit or a few nuts, slowly, away from the screen",
                                     detail: "Rest without a screen.", sources: [.microBreaks]), at: 0)
        case .move:
            menu.insert(PlanGuidance(title: "Ten squats or a quick walk around the block",
                                     detail: "A short bout of exercise sharpens attention.", sources: [.exerciseCognition]), at: 0)
        case .mix: break
        }
        return menu
    }

    func breakIdea(seed: Int) -> String {
        let menu = breakMenu
        return menu[abs(seed) % menu.count].title
    }

    var reward: PlanGuidance {
        let reward = answers.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanGuidance(
            title: reward.isEmpty ? "Something you enjoy, after the last block of the day" : reward,
            detail: "Only after the day's last block. Something you enjoy reinforces the effort that comes before it.",
            sources: [.premackPrinciple])
    }

    /// Why the ladder works the way it does.
    static let ladderGuidance = PlanGuidance(
        title: "How levels work",
        detail: "Small, specific steps beat one distant goal. You move up after \(blocksPerLevel) full blocks on \(daysPerLevel)+ days with at least \(Int(levelUpCompletion * 100))% of blocks finished, and step back a level if under \(Int(stepBackCompletion * 100))% are, so you keep succeeding.",
        sources: [.proximalGoals, .goalSetting, .selfEfficacy])

    static let breakGuidance = PlanGuidance(
        title: "Why breaks are a third of the block",
        detail: "Holding attention is hard work and fades without rest. Regular breaks restore vigour and protect the next block.",
        sources: [.vigilanceWork, .breaksVigilance, .microBreaks])
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

// MARK: - Metrics

/// Measurements of your focus over a window of days, from the blocks you record.
struct FocusMetrics: Equatable, Sendable {
    /// Share of focus blocks finished at their full planned length.
    let completionRate: Double?
    /// Median of each block's longest stretch without a pause, in minutes.
    let unbrokenMinutes: Double?
    /// Average pauses per block.
    let pausesPerBlock: Double?
    /// How tightly the day's first block starts around its usual time, in minutes
    /// (median absolute deviation). Smaller means a steadier routine.
    let startSpreadMinutes: Double?
    let activeDays: Int
    let blocks: Int

    static func measure(sessions: [FocusSession], from start: Date, to end: Date, calendar: Calendar = .current) -> FocusMetrics {
        let window = sessions.filter { $0.startedAt >= start && $0.startedAt < end && $0.focusedSeconds > 0 }
        guard !window.isEmpty else {
            return FocusMetrics(completionRate: nil, unbrokenMinutes: nil, pausesPerBlock: nil, startSpreadMinutes: nil, activeDays: 0, blocks: 0)
        }
        let full = window.filter { $0.outcome != .abandoned && $0.focusedSeconds >= $0.plannedSeconds }
        let longest = window.map { session -> Double in
            let stretches = (session.activeIntervals ?? []).compactMap { interval in
                interval.endedAt.map { $0.timeIntervalSince(interval.startedAt) }
            }
            return (stretches.max() ?? Double(session.focusedSeconds)) / 60
        }
        let pauses = window.map { Double(max(0, ($0.activeIntervals?.count ?? 1) - 1)) }
        let byDay = Dictionary(grouping: window) { calendar.startOfDay(for: $0.startedAt) }
        let firstStarts = byDay.values.compactMap { day -> Double? in
            guard let first = day.min(by: { $0.startedAt < $1.startedAt }) else { return nil }
            let parts = calendar.dateComponents([.hour, .minute], from: first.startedAt)
            return Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        }
        let spread: Double? = firstStarts.count >= 2 ? {
            let center = median(firstStarts)
            return median(firstStarts.map { abs($0 - center) })
        }() : nil
        return FocusMetrics(
            completionRate: Double(full.count) / Double(window.count),
            unbrokenMinutes: median(longest),
            pausesPerBlock: pauses.reduce(0, +) / Double(pauses.count),
            startSpreadMinutes: spread,
            activeDays: byDay.count,
            blocks: window.count
        )
    }

    /// This week and the week before, ending now.
    static func weekOverWeek(sessions: [FocusSession], now: Date = Date(), calendar: Calendar = .current) -> (current: FocusMetrics, previous: FocusMetrics) {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? now
        let earlier = calendar.date(byAdding: .day, value: -7, to: start) ?? now
        return (measure(sessions: sessions, from: start, to: end, calendar: calendar),
                measure(sessions: sessions, from: earlier, to: start, calendar: calendar))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
