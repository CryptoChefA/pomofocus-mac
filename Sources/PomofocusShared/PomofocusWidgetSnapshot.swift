import Foundation

public enum PomofocusWidgetPhase: String, Codable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var compactTitle: String {
        switch self {
        case .focus: "FOCUS"
        case .shortBreak: "REST"
        case .longBreak: "LONG REST"
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
        case .idle: "READY"
        case .breathing: "BREATHE"
        case .running: "IN PROGRESS"
        case .paused: "PAUSED"
        case .overtime: "OVERTIME"
        case .completed: "COMPLETE"
        }
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
        todayFocusSeconds: Int
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
}

public enum PomofocusWidgetSnapshotStore {
    public static let fileName = "widget-state.json"

    public static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Pomofocus", isDirectory: true)
            .appendingPathComponent(fileName)
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
