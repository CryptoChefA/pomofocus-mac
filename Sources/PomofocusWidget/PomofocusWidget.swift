import Foundation
import PomofocusShared
import SwiftUI
import WidgetKit

private struct PomofocusEntry: TimelineEntry {
    let date: Date
    let snapshot: PomofocusWidgetSnapshot
}

private struct PomofocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> PomofocusEntry {
        PomofocusEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (PomofocusEntry) -> Void) {
        completion(PomofocusEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PomofocusEntry>) -> Void) {
        let now = Date()
        let snapshot = loadSnapshot()
        let nextRefresh = snapshot.endDate.map { max($0, now.addingTimeInterval(60)) }
            ?? now.addingTimeInterval(15 * 60)
        completion(Timeline(
            entries: [PomofocusEntry(date: now, snapshot: snapshot)],
            policy: .after(nextRefresh)
        ))
    }

    private func loadSnapshot() -> PomofocusWidgetSnapshot {
        (try? PomofocusWidgetSnapshotStore.load()) ?? .placeholder
    }
}

private enum WidgetPalette {
    static let black = Color(red: 0.025, green: 0.028, blue: 0.032)
    static let white = Color(red: 0.945, green: 0.937, blue: 0.914)
    static let secondary = Color(red: 0.56, green: 0.58, blue: 0.61)
    static let track = Color.white.opacity(0.11)
    static let gold = Color(red: 0.741, green: 0.647, blue: 0.435)
}

private struct PomofocusWidgetView: View {
    let entry: PomofocusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallView
            case .systemMedium:
                mediumView
            default:
                largeView
            }
        }
        .containerBackground(for: .widget) { WidgetPalette.black }
        .environment(\.colorScheme, .dark)
        .widgetURL(URL(string: "pomofocus://focus"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                WidgetMark(size: 18)
                Text(entry.snapshot.phase.compactTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(WidgetPalette.white)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 8)
            timerText(size: 34)
            Spacer(minLength: 8)
            ProgressBand(snapshot: entry.snapshot)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        WidgetMark(size: 17)
                        Text(entry.snapshot.phase.compactTitle)
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(1.35)
                    }
                    timerText(size: 38)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.snapshot.taskName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetPalette.white)
                        .lineLimit(1)
                    if !entry.snapshot.intention.isEmpty {
                        Text(entry.snapshot.intention)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(1)
                    }
                    Text("\(entry.snapshot.cycleCurrent) OF \(entry.snapshot.cycleTotal)")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(WidgetPalette.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProgressBand(snapshot: entry.snapshot)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WidgetMark(size: 19)
                Text("POMOFOCUS")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(WidgetPalette.white)
                Spacer()
                Text(entry.snapshot.status.compactTitle)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.25)
                    .foregroundStyle(WidgetPalette.secondary)
            }

            Spacer(minLength: 20)

            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    timerText(size: 50)
                    Text(entry.snapshot.phase.compactTitle)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(WidgetPalette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.snapshot.taskName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WidgetPalette.white)
                        .lineLimit(1)
                    if !entry.snapshot.intention.isEmpty {
                        Text(entry.snapshot.intention)
                            .font(.system(size: 13))
                            .foregroundStyle(WidgetPalette.secondary)
                            .lineLimit(2)
                    }
                    Text("SESSION \(entry.snapshot.cycleCurrent) OF \(entry.snapshot.cycleTotal)")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.05)
                        .foregroundStyle(WidgetPalette.secondary)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 20)

            HStack {
                Text("TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.25)
                    .foregroundStyle(WidgetPalette.secondary)
                Spacer()
                Text(durationString(entry.snapshot.todayFocusSeconds))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(WidgetPalette.white)
            }
            .padding(.bottom, 9)

            ProgressBand(snapshot: entry.snapshot)
        }
    }

    @ViewBuilder
    private func timerText(size: CGFloat) -> some View {
        let snapshot = entry.snapshot
        Group {
            if snapshot.status == .running,
               let endDate = snapshot.endDate {
                let startDate = endDate.addingTimeInterval(TimeInterval(-snapshot.plannedSeconds))
                Text(
                    timerInterval: startDate...endDate,
                    countsDown: true,
                    showsHours: snapshot.plannedSeconds >= 3_600
                )
            } else if snapshot.status == .overtime,
                      let overtimeStart = snapshot.overtimeStartDate {
                HStack(spacing: 0) {
                    Text("+")
                    Text(overtimeStart, style: .timer)
                }
            } else {
                Text(clockString(snapshot.remainingSeconds))
            }
        }
        .font(.system(size: size, weight: .medium, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(WidgetPalette.white)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private func clockString(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        let remainder = safe % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func durationString(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3_600
        let minutes = (safe % 3_600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)H \(minutes)M" : "\(hours)H" }
        return "\(minutes)M"
    }
}

private struct ProgressBand: View {
    let snapshot: PomofocusWidgetSnapshot

    var body: some View {
        Group {
            if snapshot.status == .running,
               let endDate = snapshot.endDate {
                let startDate = endDate.addingTimeInterval(TimeInterval(-snapshot.plannedSeconds))
                ProgressView(timerInterval: startDate...endDate, countsDown: true)
            } else {
                ProgressView(value: max(0, min(1, 1 - snapshot.progress)))
            }
        }
        .progressViewStyle(.linear)
        .tint(WidgetPalette.gold)
        .background(WidgetPalette.track)
        .clipShape(Capsule())
        .frame(height: 3)
    }
}

private struct WidgetMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.07, to: 0.93)
                .stroke(WidgetPalette.white, style: StrokeStyle(lineWidth: 2.1, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Capsule()
                .fill(WidgetPalette.white)
                .frame(width: size * 0.42, height: 2.1)
                .rotationEffect(.degrees(34), anchor: .leading)
                .offset(x: size * 0.11, y: size * 0.08)
        }
        .frame(width: size, height: size)
    }
}

private struct PomofocusTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PomofocusWidgetSnapshot.kind, provider: PomofocusProvider()) { entry in
            PomofocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Pomofocus")
        .description("Your current focus block, kept private and local.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .containerBackgroundRemovable(false)
    }
}

@main
struct PomofocusWidgetBundle: WidgetBundle {
    var body: some Widget {
        PomofocusTimerWidget()
    }
}
