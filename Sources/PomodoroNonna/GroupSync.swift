import Foundation

/// The timer, as a study group's host shares it. Only what's needed to keep everyone's timer
/// in step: no tasks, notes, ratings or history ever go into it.
struct GroupTimer: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Nothing timing: before a block, between them, or in the breathing ritual.
        case idle
        case running
        case paused
    }

    /// Identifies the host's current block, so a new block is told apart from the same one.
    var blockID: String?
    var phase: TimerPhase
    var state: State
    /// The block's planned length, in seconds.
    var planned: Int
    /// Seconds of the block done when this was sent.
    var elapsed: Double
    var sentAt: Date
    var hostName: String
    /// First names of everyone in the group, host first.
    var members: [String]

    /// The block's progress now, counting on from when it was sent while it runs.
    func elapsed(at now: Date) -> Double {
        state == .running ? elapsed + max(0, now.timeIntervalSince(sentAt)) : elapsed
    }
}

/// A message between Macs in a group.
struct GroupMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case hello, timer }
    var kind: Kind
    /// With `hello`: the first name someone joins as.
    var name: String?
    var timer: GroupTimer?
}

/// What a friend's Mac does to follow the host: a pure decision, so it can be checked on its
/// own. The Mac acting on it records its own blocks as usual.
enum GroupSync {
    /// The friend's own timer, as far as following goes.
    struct Local: Equatable {
        /// The host block this timer is following, if any.
        var followingBlock: String?
        var phase: TimerPhase
        /// Idle, running (overtime included) or paused.
        var state: GroupTimer.State
        var planned: Int
        var elapsed: Double
    }

    enum Action: Equatable {
        case none
        /// The host's block ended: finish this one, and wait on the host's next phase.
        case stop(nextPhase: TimerPhase)
        /// Nothing running here, but the host has moved to another phase.
        case select(TimerPhase)
        /// Start the host's block partway through (finishing this Mac's own block first, if
        /// one is running).
        case start(blockID: String, phase: TimerPhase, planned: Int, elapsed: Double, paused: Bool)
        case pause
        case resume(elapsed: Double)
        /// Same block, but drifted or changed length: line it up again.
        case align(planned: Int, elapsed: Double)
    }

    /// Seconds two timers may differ before they're lined up again. Under it, the difference
    /// is the time a message takes; correcting it would make the clock jitter.
    static let tolerance: Double = 2

    static func action(local: Local, host: GroupTimer, now: Date) -> Action {
        guard host.state != .idle, let block = host.blockID else {
            if local.state != .idle { return .stop(nextPhase: host.phase) }
            return local.phase == host.phase ? .none : .select(host.phase)
        }
        let hostElapsed = host.elapsed(at: now)
        if local.followingBlock != block || local.state == .idle || local.phase != host.phase {
            return .start(blockID: block, phase: host.phase, planned: host.planned, elapsed: hostElapsed,
                          paused: host.state == .paused)
        }
        if host.state == .paused, local.state == .running { return .pause }
        if host.state == .running, local.state == .paused { return .resume(elapsed: hostElapsed) }
        if abs(local.elapsed - hostElapsed) > tolerance || local.planned != host.planned {
            return .align(planned: host.planned, elapsed: hostElapsed)
        }
        return .none
    }
}
