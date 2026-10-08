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
        case .focus: "FOCUS"
        case .shortBreak: "REST"
        case .longBreak: "LONG REST"
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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .ticking: "Soft ticking"
        case .rain: "Gentle rain"
        case .ocean: "Ocean waves"
        case .brownNoise: "Brown noise"
        }
    }

    var subtitle: String {
        switch self {
        case .off: "Silence while you focus"
        case .ticking: "A quiet clock pulse"
        case .rain: "Soft droplets on a window"
        case .ocean: "Slow, rolling surf"
        case .brownNoise: "Low and calming"
        }
    }

    var icon: String {
        switch self {
        case .off: "speaker.slash"
        case .ticking: "metronome"
        case .rain: "cloud.rain.fill"
        case .ocean: "water.waves"
        case .brownNoise: "waveform"
        }
    }
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

    var duration: TimeInterval { TimeInterval(focusedSeconds) }
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

    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, longBreakEvery
        case dailyGoalMinutes, allowOvertime, autoStartBreaks, autoStartFocus
        case breathingEnabled, breathingSeconds, presenceChimeMinutes, overtimeReminderMinutes, playSounds
        case ambientSound, ambientVolume, showInMenuBar
        case showCalendarEvents, hiddenCalendarIDs, overtimeAlert
        case celebrateSessions
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
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(focusMinutes, forKey: .focusMinutes)
        try values.encode(celebrateSessions, forKey: .celebrateSessions)
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
