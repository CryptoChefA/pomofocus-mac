import Foundation
import SwiftUI

enum TimerPhase: String, Codable, CaseIterable, Sendable {
    case focus
    case shortBreak
    case longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    var compactTitle: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Rest"
        case .longBreak: "Long rest"
        }
    }
}

enum TimerStatus: String, Codable, Sendable {
    case idle
    case running
    case paused
    case overtime
}

enum BreathingStage: String, Sendable {
    case inhale
    case exhale

    var prompt: String {
        switch self {
        case .inhale: "Deep breath in"
        case .exhale: "Deep breath out"
        }
    }
}

enum SessionOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case finishedEarly
    case abandoned

    var title: String {
        switch self {
        case .completed: "Completed"
        case .finishedEarly: "Finished early"
        case .abandoned: "Abandoned"
        }
    }
}

enum AmbientSound: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case ticking
    case rain
    case ocean
    case brownNoise
    case whiteNoise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .ticking: "Clock ticking"
        case .rain: "Rain"
        case .ocean: "Ocean waves"
        case .brownNoise: "Brown noise"
        case .whiteNoise: "White noise"
        }
    }

    var subtitle: String {
        switch self {
        case .off: "Silence while you focus"
        case .ticking: "An old wall clock, steady and slow"
        case .rain: "Rain against a window"
        case .ocean: "Slow waves on a beach"
        case .brownNoise: "Deep and soft, like distant wind"
        case .whiteNoise: "A gentle hush, never hissy"
        }
    }

    var icon: String {
        switch self {
        case .off: "speaker.slash"
        case .ticking: "clock"
        case .rain: "cloud.rain.fill"
        case .ocean: "water.waves"
        case .brownNoise: "waveform"
        case .whiteNoise: "wind"
        }
    }

    /// The loop in Resources/Sounds.
    var fileName: String? {
        switch self {
        case .off: nil
        case .ticking: "clock"
        case .rain: "rain"
        case .ocean: "ocean"
        case .brownNoise: "brown"
        case .whiteNoise: "white"
        }
    }

    /// Where the recordings come from. The clock's licence asks for this credit.
    static let credits = "Clock: \u{201C}Wall clock with weight ticking\u{201D} by Work With Sounds / Technical Museum of Slovenia, CC BY 4.0. Rain: \u{201C}Rain against the window\u{201D}, public domain. Ocean: \u{201C}Ocean Waves on a Tropical Beach\u{201D}, CC0. All via Wikimedia Commons; trimmed and looped. Brown and white noise made for Pomofocus."
}

struct FocusTask: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var colorHex: String
    var createdAt: Date = Date()
    var isArchived: Bool = false
}

struct SessionImageAttachment: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var fileName: String
    var displayWidth: Double = 200
    var caption: String = ""
}

struct SessionDraft: Codable, Equatable, Sendable {
    var taskID: UUID?
    var intention: String
    var note: String
    var attachments: [SessionImageAttachment]
    var todoID: UUID? = nil
}

struct ActivityInterval: Codable, Hashable, Sendable {
    var startedAt: Date
    var endedAt: Date?

    func duration(through date: Date = Date()) -> TimeInterval {
        max(0, (endedAt ?? date).timeIntervalSince(startedAt))
    }
}

struct FocusSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var taskID: UUID?
    var taskName: String
    var intention: String
    var note: String
    var startedAt: Date
    var endedAt: Date
    var focusedSeconds: Int
    var pausedSeconds: Int
    var plannedSeconds: Int
    var outcome: SessionOutcome
    var focusRating: Int?
    var attachments: [SessionImageAttachment]? = nil
    var activeIntervals: [ActivityInterval]? = nil
    /// The to-do this block was for, if any.
    var todoID: UUID? = nil
    /// Shared by the parts of one block that was split when the list changed part-way.
    var blockID: UUID? = nil

    var duration: TimeInterval { TimeInterval(focusedSeconds) }
}

extension FocusSession {
    /// Joins the parts of split blocks back into one block each, for counting blocks,
    /// finish rates and plan progress. Time per list still uses the separate parts.
    static func mergedBlocks(_ sessions: [FocusSession]) -> [FocusSession] {
        var result: [FocusSession] = []
        var indexByBlock: [UUID: Int] = [:]
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard let block = session.blockID else {
                result.append(session)
                continue
            }
            if let index = indexByBlock[block] {
                var merged = result[index]
                merged.focusedSeconds += session.focusedSeconds
                merged.pausedSeconds += session.pausedSeconds
                merged.plannedSeconds += session.plannedSeconds
                merged.endedAt = max(merged.endedAt, session.endedAt)
                merged.activeIntervals = (merged.activeIntervals ?? []) + (session.activeIntervals ?? [])
                merged.outcome = session.outcome
                merged.focusRating = session.focusRating ?? merged.focusRating
                result[index] = merged
            } else {
                indexByBlock[block] = result.count
                result.append(session)
            }
        }
        return result
    }
}

/// An earlier part of a running block that changed list part-way.
struct BlockSegment: Codable, Equatable, Sendable {
    let taskID: UUID?
    let taskName: String
    let intention: String
    let todoID: UUID?
    let endsAt: Date
}

struct BreakSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var phase: TimerPhase
    var startedAt: Date
    var endedAt: Date
    var restedSeconds: Int
    var pausedSeconds: Int
    var plannedSeconds: Int
    var wasSkipped: Bool
    var activeIntervals: [ActivityInterval]? = nil

    var overtimeSeconds: Int { max(0, restedSeconds - plannedSeconds) }
    var plannedRestSeconds: Int { min(restedSeconds, plannedSeconds) }
}

struct NonnaSettings: Codable, Equatable, Sendable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 20
    var longBreakEvery = 4
    var dailyGoalMinutes = 120
    var allowOvertime = true
    var autoStartBreaks = false
    var autoStartFocus = false
    var breathingEnabled = true
    var presenceChimeMinutes = 10
    var overtimeReminderMinutes = 1
    var overtimeAlert = true
    var playSounds = true
    var ambientSound: AmbientSound = .off
    var ambientVolume = 0.32
    var showInMenuBar = true
    var showCalendarEvents = false
    var hiddenCalendarIDs: [String] = []
    var celebrateSessions = true
    /// When a timer has run past its planned time and the Mac sees no keyboard or mouse
    /// for `awayMinutes` (or sleeps, or locks), pause it as of the moment you left.
    var pauseWhenAway = true
    var awayMinutes = 10
    /// When to ask "how focused were you?".
    var rateFocus: RatingTiming = .endOfSession
    /// Themes added from codes, shared or rare.
    var savedThemes: [SharedTheme] = []
    /// How the end of a session is celebrated.
    var celebrationStyle: CelebrationStyle = .confetti
    /// Tasks shows what's next instead of everything at once, adding a task asks only for
    /// its name, and after a few minutes of planning the app suggests starting.
    var simpleTasks = true
    /// A `ThemeChoice` raw value.
    var themeID = ThemeChoice.obsidian.rawValue
    var customTheme = CustomThemeSpec()
    /// New installs see the welcome screen once; data saved before it existed skips it.
    var hasCompletedOnboarding = false

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case dailyGoalMinutes, allowOvertime, autoStartBreaks, autoStartFocus
        case breathingEnabled, breathingSeconds, presenceChimeMinutes, overtimeReminderMinutes, playSounds
        case ambientSound, ambientVolume, showInMenuBar
        case showCalendarEvents, hiddenCalendarIDs, overtimeAlert
        case celebrateSessions, themeID, customTheme, hasCompletedOnboarding
        case pauseWhenAway, awayMinutes, rateFocus, savedThemes, celebrationStyle, simpleTasks
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        focusMinutes = try values.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 25
        shortBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? 5
        longBreakMinutes = try values.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? 20
        longBreakEvery = try values.decodeIfPresent(Int.self, forKey: .longBreakEvery) ?? 4
        dailyGoalMinutes = try values.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? 120
        allowOvertime = try values.decodeIfPresent(Bool.self, forKey: .allowOvertime) ?? true
        autoStartBreaks = try values.decodeIfPresent(Bool.self, forKey: .autoStartBreaks) ?? false
        autoStartFocus = try values.decodeIfPresent(Bool.self, forKey: .autoStartFocus) ?? false
        if let enabled = try values.decodeIfPresent(Bool.self, forKey: .breathingEnabled) {
            breathingEnabled = enabled
        } else {
            let legacySeconds = try values.decodeIfPresent(Int.self, forKey: .breathingSeconds) ?? 3
            breathingEnabled = legacySeconds > 0
        }
        presenceChimeMinutes = try values.decodeIfPresent(Int.self, forKey: .presenceChimeMinutes) ?? 10
        overtimeReminderMinutes = try values.decodeIfPresent(Int.self, forKey: .overtimeReminderMinutes) ?? 1
        playSounds = try values.decodeIfPresent(Bool.self, forKey: .playSounds) ?? true
        ambientSound = try values.decodeIfPresent(AmbientSound.self, forKey: .ambientSound) ?? .off
        ambientVolume = try values.decodeIfPresent(Double.self, forKey: .ambientVolume) ?? 0.32
        showInMenuBar = try values.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true
        showCalendarEvents = try values.decodeIfPresent(Bool.self, forKey: .showCalendarEvents) ?? false
        overtimeAlert = try values.decodeIfPresent(Bool.self, forKey: .overtimeAlert) ?? true
        hiddenCalendarIDs = try values.decodeIfPresent([String].self, forKey: .hiddenCalendarIDs) ?? []
        celebrateSessions = try values.decodeIfPresent(Bool.self, forKey: .celebrateSessions) ?? true
        pauseWhenAway = try values.decodeIfPresent(Bool.self, forKey: .pauseWhenAway) ?? true
        awayMinutes = try values.decodeIfPresent(Int.self, forKey: .awayMinutes) ?? 10
        rateFocus = try values.decodeIfPresent(RatingTiming.self, forKey: .rateFocus) ?? .endOfSession
        savedThemes = try values.decodeIfPresent([SharedTheme].self, forKey: .savedThemes) ?? []
        celebrationStyle = try values.decodeIfPresent(CelebrationStyle.self, forKey: .celebrationStyle) ?? .confetti
        simpleTasks = try values.decodeIfPresent(Bool.self, forKey: .simpleTasks) ?? true
        themeID = try values.decodeIfPresent(String.self, forKey: .themeID) ?? ThemeChoice.obsidian.rawValue
        customTheme = try values.decodeIfPresent(CustomThemeSpec.self, forKey: .customTheme) ?? CustomThemeSpec()
        hasCompletedOnboarding = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(focusMinutes, forKey: .focusMinutes)
        try values.encode(celebrateSessions, forKey: .celebrateSessions)
        try values.encode(pauseWhenAway, forKey: .pauseWhenAway)
        try values.encode(awayMinutes, forKey: .awayMinutes)
        try values.encode(rateFocus, forKey: .rateFocus)
        try values.encode(savedThemes, forKey: .savedThemes)
        try values.encode(celebrationStyle, forKey: .celebrationStyle)
        try values.encode(simpleTasks, forKey: .simpleTasks)
        try values.encode(themeID, forKey: .themeID)
        try values.encode(customTheme, forKey: .customTheme)
        try values.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try values.encode(shortBreakMinutes, forKey: .shortBreakMinutes)
        try values.encode(longBreakMinutes, forKey: .longBreakMinutes)
        try values.encode(longBreakEvery, forKey: .longBreakEvery)
        try values.encode(dailyGoalMinutes, forKey: .dailyGoalMinutes)
        try values.encode(allowOvertime, forKey: .allowOvertime)
        try values.encode(autoStartBreaks, forKey: .autoStartBreaks)
        try values.encode(autoStartFocus, forKey: .autoStartFocus)
        try values.encode(breathingEnabled, forKey: .breathingEnabled)
        try values.encode(presenceChimeMinutes, forKey: .presenceChimeMinutes)
        try values.encode(overtimeReminderMinutes, forKey: .overtimeReminderMinutes)
        try values.encode(playSounds, forKey: .playSounds)
        try values.encode(ambientSound, forKey: .ambientSound)
        try values.encode(ambientVolume, forKey: .ambientVolume)
        try values.encode(showInMenuBar, forKey: .showInMenuBar)
        try values.encode(showCalendarEvents, forKey: .showCalendarEvents)
        try values.encode(overtimeAlert, forKey: .overtimeAlert)
        try values.encode(hiddenCalendarIDs, forKey: .hiddenCalendarIDs)
    }
}

struct ActiveTimerSnapshot: Codable, Equatable, Sendable {
    var phase: TimerPhase
    var status: TimerStatus
    var taskID: UUID?
    var intention: String
    var note: String
    var startedAt: Date
    var lastSavedAt: Date
    var remainingSeconds: Int
    var elapsedSeconds: Int
    var pausedSeconds: Int
    var plannedSeconds: Int
    var isOvertime: Bool
    var attachments: [SessionImageAttachment]? = nil
    var activeIntervals: [ActivityInterval]? = nil
    var todoID: UUID? = nil
    /// Earlier parts of the block, if the list changed part-way through it.
    var segments: [BlockSegment]? = nil
}

struct AppData: Codable, Sendable {
    var tasks: [FocusTask]
    var sessions: [FocusSession]
    var settings: NonnaSettings
    var activeTimer: ActiveTimerSnapshot?
    var draft: SessionDraft? = nil
    var pendingPhase: TimerPhase? = nil
    var breaks: [BreakSession]? = nil
    /// When the current sitting (a run of pomodoros and breaks) began. Cleared by End session.
    var runStartedAt: Date? = nil
    /// The dopamine focus plan, if one has been built.
    var focusPlan: FocusPlan? = nil
    /// To-dos, organised into the task lists above.
    var todos: [TodoItem]? = nil

    static let starter = AppData(
        tasks: [
            FocusTask(name: "Deep work", colorHex: "BDA56F"),
            FocusTask(name: "Study", colorHex: "738B80"),
            FocusTask(name: "Creative", colorHex: "A9A4B5")
        ],
        sessions: [],
        settings: NonnaSettings(),
        activeTimer: nil
    )
}

struct TaskTotal: Identifiable, Equatable, Sendable {
    let taskID: UUID?
    let name: String
    let colorHex: String
    let seconds: Int
    let sessionCount: Int

    var id: String { taskID?.uuidString ?? "uncategorized-\(name)" }
}

struct DayTotal: Identifiable, Equatable, Sendable {
    let day: Date
    let seconds: Int
    var id: Date { day }
}

struct AnalyticsSnapshot: Equatable, Sendable {
    let totalFocusSeconds: Int
    let usedDays: Int
    let completedSessions: Int
    let currentStreak: Int
    let longestStreak: Int
    let taskTotals: [TaskTotal]
    let recentDays: [DayTotal]

    static func calculate(
        sessions: [FocusSession],
        tasks: [FocusTask],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let focusSessions = sessions.filter { $0.focusedSeconds > 0 && $0.outcome != .abandoned }
        let taskMap = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let grouped = Dictionary(grouping: focusSessions) { session in
            session.taskID?.uuidString ?? "name:\(session.taskName.lowercased())"
        }

        let taskTotals = grouped.values.map { group -> TaskTotal in
            let first = group[0]
            let task = first.taskID.flatMap { taskMap[$0] }
            return TaskTotal(
                taskID: first.taskID,
                name: task?.name ?? (first.taskName.isEmpty ? "Uncategorized" : first.taskName),
                colorHex: task?.colorHex ?? "8D8379",
                seconds: group.reduce(0) { $0 + $1.focusedSeconds },
                sessionCount: group.count
            )
        }.sorted { $0.seconds > $1.seconds }

        let groupedDays = Dictionary(grouping: focusSessions) {
            calendar.startOfDay(for: $0.startedAt)
        }
        let usedDaySet = Set(groupedDays.keys)
        let recentStart = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        let recentDays = (0..<14).compactMap { offset -> DayTotal? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: recentStart) else { return nil }
            let seconds = groupedDays[day, default: []].reduce(0) { $0 + $1.focusedSeconds }
            return DayTotal(day: day, seconds: seconds)
        }

        let sortedDays = usedDaySet.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in sortedDays {
            if let previous,
               calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var current = 0
        var cursor = usedDaySet.contains(today) ? today : yesterday
        while usedDaySet.contains(cursor) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        return AnalyticsSnapshot(
            totalFocusSeconds: focusSessions.reduce(0) { $0 + $1.focusedSeconds },
            usedDays: usedDaySet.count,
            completedSessions: focusSessions.filter { $0.outcome == .completed }.count,
            currentStreak: current,
            longestStreak: longest,
            taskTotals: taskTotals,
            recentDays: recentDays
        )
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        let r, g, b: Double
        if clean.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 0.55; g = 0.51; b = 0.47
        }
        self.init(red: r, green: g, blue: b)
    }
}

extension Int {
    var clockString: String {
        let value = Swift.max(0, self)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    var focusDurationString: String {
        if self <= 0 { return "0m" }
        let hours = self / 3600
        let minutes = (self % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
    }
}

/// When Pomofocus asks you to rate your focus.
enum RatingTiming: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyBlock, endOfSession, never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyBlock: "After every block"
        case .endOfSession: "When I end a session"
        case .never: "Never"
        }
    }
}

/// The show at the end of a session.
enum CelebrationStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case confetti, fireworks, balloons, surprise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .confetti: "Confetti"
        case .fireworks: "Fireworks"
        case .balloons: "Balloons"
        case .surprise: "Surprise me"
        }
    }

    /// The style to actually play: "Surprise me" picks one of the others.
    var resolved: CelebrationStyle {
        self == .surprise ? [.confetti, .fireworks, .balloons].randomElement() ?? .confetti : self
    }
}
