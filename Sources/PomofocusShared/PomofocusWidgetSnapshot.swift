import Foundation

public enum PomofocusWidgetPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var compactTitle: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Rest"
        case .longBreak: "Long rest"
        }
    }
}

public enum PomofocusWidgetStatus: String, Codable, Sendable {
    case idle
    case breathing
    case running
    case paused
    case overtime
    case completed

    public var compactTitle: String {
        switch self {
        case .idle: "Ready"
        case .breathing: "Breathe"
        case .running: "In progress"
        case .paused: "Paused"
        case .overtime: "Overtime"
        case .completed: "Complete"
        }
    }
}

/// The app's theme colours, as hex, so the widget matches whatever look is chosen.
public struct PomofocusWidgetTheme: Codable, Equatable, Sendable {
    public var isDark: Bool
    public var background: String
    public var ink: String
    public var secondaryInk: String
    public var line: String
    public var accent: String

    public init(isDark: Bool, background: String, ink: String, secondaryInk: String, line: String, accent: String) {
        self.isDark = isDark
        self.background = background
        self.ink = ink
        self.secondaryInk = secondaryInk
        self.line = line
        self.accent = accent
    }
}

public struct PomofocusWidgetSnapshot: Codable, Equatable, Sendable {
    public static let kind = "PomofocusTimerWidget"

    public var phase: PomofocusWidgetPhase
    public var status: PomofocusWidgetStatus
    public var taskName: String
    public var intention: String
    public var updatedAt: Date
    public var plannedSeconds: Int
    public var remainingSeconds: Int
    public var elapsedSeconds: Int
    public var progress: Double
    public var endDate: Date?
    public var overtimeStartDate: Date?
    public var cycleCurrent: Int
    public var cycleTotal: Int
    public var todayFocusSeconds: Int
    /// Missing in files written before themes reached the widget.
    public var theme: PomofocusWidgetTheme?

    public init(
        phase: PomofocusWidgetPhase,
        status: PomofocusWidgetStatus,
        taskName: String,
        intention: String,
        updatedAt: Date,
        plannedSeconds: Int,
        remainingSeconds: Int,
        elapsedSeconds: Int,
        progress: Double,
        endDate: Date?,
        overtimeStartDate: Date?,
        cycleCurrent: Int,
        cycleTotal: Int,
        todayFocusSeconds: Int,
        theme: PomofocusWidgetTheme? = nil
    ) {
        self.phase = phase
        self.status = status
        self.taskName = taskName
        self.intention = intention
        self.updatedAt = updatedAt
        self.plannedSeconds = plannedSeconds
        self.remainingSeconds = remainingSeconds
        self.elapsedSeconds = elapsedSeconds
        self.progress = progress
        self.endDate = endDate
        self.overtimeStartDate = overtimeStartDate
        self.cycleCurrent = cycleCurrent
        self.cycleTotal = cycleTotal
        self.todayFocusSeconds = todayFocusSeconds
        self.theme = theme
    }

    public static let placeholder = PomofocusWidgetSnapshot(
        phase: .focus,
        status: .running,
        taskName: "Deep work",
        intention: "One meaningful thing",
        updatedAt: Date(),
        plannedSeconds: 25 * 60,
        remainingSeconds: 18 * 60 + 42,
        elapsedSeconds: 6 * 60 + 18,
        progress: 0.252,
        endDate: Date().addingTimeInterval(18 * 60 + 42),
        overtimeStartDate: nil,
        cycleCurrent: 2,
        cycleTotal: 4,
        todayFocusSeconds: 106 * 60
    )

    /// Shown when the app hasn't written anything yet: a quiet, idle timer, never made-up numbers.
    public static var idle: PomofocusWidgetSnapshot {
        PomofocusWidgetSnapshot(
            phase: .focus, status: .idle, taskName: "", intention: "", updatedAt: Date(),
            plannedSeconds: 25 * 60, remainingSeconds: 25 * 60, elapsedSeconds: 0, progress: 0,
            endDate: nil, overtimeStartDate: nil, cycleCurrent: 1, cycleTotal: 4, todayFocusSeconds: 0
        )
    }
}

public enum PomofocusWidgetSnapshotStore {
    public static let fileName = "widget-state.json"

    public static var fileURL: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support/Pomofocus", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Where the app's data lives. Inside the sandboxed widget,
    /// `homeDirectoryForCurrentUser` points at the widget's own container, where the app's
    /// snapshot never is; the password database still gives the real path, which the
    /// widget's read-only entitlement allows it to read.
    static var realHomeDirectory: URL {
        // Only the sandboxed widget needs this. The app itself keeps using the normal home,
        // which respects CFFIXED_USER_HOME, so test builds never touch real data.
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
           let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public static func save(_ snapshot: PomofocusWidgetSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public static func load() throws -> PomofocusWidgetSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            PomofocusWidgetSnapshot.self,
            from: Data(contentsOf: fileURL)
        )
    }
}
