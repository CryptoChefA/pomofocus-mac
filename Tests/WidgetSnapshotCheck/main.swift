import Foundation

@main
struct WidgetSnapshotCheck {
    static func main() {
        do {
            let snapshot = try PomofocusWidgetSnapshotStore.load()
            print("\(snapshot.phase.rawValue):\(snapshot.status.rawValue):\(snapshot.remainingSeconds)")
        } catch {
            fputs("Widget snapshot read failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
