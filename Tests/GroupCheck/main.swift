import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

let now = Date(timeIntervalSince1970: 1_790_000_000)
func host(_ block: String?, _ phase: TimerPhase = .focus, _ state: GroupTimer.State = .running,
          planned: Int = 1500, elapsed: Double = 300, sentAgo: Double = 1) -> GroupTimer {
    GroupTimer(blockID: block, phase: phase, state: state, planned: planned, elapsed: elapsed,
               sentAt: now.addingTimeInterval(-sentAgo), hostName: "Sam", members: ["Sam", "Alex"])
}
func local(_ block: String?, _ phase: TimerPhase = .focus, _ state: GroupTimer.State = .running,
           planned: Int = 1500, elapsed: Double = 301) -> GroupSync.Local {
    GroupSync.Local(followingBlock: block, phase: phase, state: state, planned: planned, elapsed: elapsed)
}

// Joining mid-block starts the host's block partway through, counting the message's travel.
check(GroupSync.action(local: local(nil, .focus, .idle, elapsed: 0), host: host("b1"), now: now)
      == .start(blockID: "b1", phase: .focus, planned: 1500, elapsed: 301, paused: false),
      "a friend joining mid-block starts at the host's point")
// In step: nothing to do.
check(GroupSync.action(local: local("b1"), host: host("b1"), now: now) == .none, "in step within tolerance")
// Drifted by more than two seconds: line up.
check(GroupSync.action(local: local("b1", elapsed: 290), host: host("b1"), now: now) == .align(planned: 1500, elapsed: 301),
      "drift is corrected")
// The host pauses, then resumes.
check(GroupSync.action(local: local("b1"), host: host("b1", .focus, .paused, elapsed: 301, sentAgo: 30), now: now) == .pause,
      "pausing follows the host")
check(GroupSync.action(local: local("b1", .focus, .paused), host: host("b1"), now: now) == .resume(elapsed: 301),
      "resuming follows the host")
// The host moves to a break: a new block, so the friend's focus block finishes and the break starts.
check(GroupSync.action(local: local("b1"), host: host("b2", .shortBreak, elapsed: 2, sentAgo: 0), now: now)
      == .start(blockID: "b2", phase: .shortBreak, planned: 1500, elapsed: 2, paused: false),
      "breaks start together")
// The host's block ends and nothing is running: stop and wait on the host's next phase.
check(GroupSync.action(local: local("b2", .shortBreak), host: host(nil, .focus, .idle, elapsed: 0), now: now) == .stop(nextPhase: .focus),
      "when the host stops, the friend stops")
check(GroupSync.action(local: local(nil, .focus, .idle, elapsed: 0), host: host(nil, .shortBreak, .idle, elapsed: 0), now: now) == .select(.shortBreak),
      "idle friends follow the host's tab")
// A paused host block isn't counted on while it waits.
check(host("b1", .focus, .paused, elapsed: 100, sentAgo: 60).elapsed(at: now) == 100, "paused time doesn't count")
// Breathing together: the host's opening breaths start the friend's, in step.
var breathing = host(nil, .focus, .idle, elapsed: 0); breathing.breathingLeft = 24
check(GroupSync.action(local: local(nil, .focus, .idle, elapsed: 0), host: breathing, now: now)
      == .breathe(phase: .focus, remaining: 24), "a host's breaths start the friend's")
var inStep = local(nil, .focus, .idle, elapsed: 0); inStep.breathingLeft = 23.6
check(GroupSync.action(local: inStep, host: breathing, now: now) == .none, "breaths within a second are in step")
inStep.breathingLeft = 21
check(GroupSync.action(local: inStep, host: breathing, now: now) == .breathe(phase: .focus, remaining: 24), "drifting breaths line up")
var lastSecond = breathing; lastSecond.breathingLeft = 0.4
check(GroupSync.action(local: local(nil, .focus, .idle, elapsed: 0), host: lastSecond, now: now) == .none,
      "no breaths started in the last second")
inStep.breathingLeft = 0.6
check(GroupSync.action(local: inStep, host: lastSecond, now: now) == .none, "the last breath isn't cut short")
check(GroupSync.action(local: inStep, host: host(nil, .focus, .idle, elapsed: 0), now: now) == .stopBreathing,
      "the host cancelling the breaths cancels the friend's")
// Older hosts don't send breaths; their messages still read.
let old = #"{"blockID":null,"phase":"focus","state":"idle","planned":1500,"elapsed":0,"sentAt":0,"hostName":"Sam","members":["Sam"]}"#
check((try? JSONDecoder().decode(GroupTimer.self, from: Data(old.utf8)))?.breathingLeft == nil, "messages without breaths still decode")

// Messages survive the trip.
let message = GroupMessage(kind: .timer, name: nil, timer: host("b1"))
let decoded = try! JSONDecoder().decode(GroupMessage.self, from: JSONEncoder().encode(message))
check(decoded.timer == message.timer && decoded.kind == .timer, "messages encode and decode")

print("Group checks passed")
