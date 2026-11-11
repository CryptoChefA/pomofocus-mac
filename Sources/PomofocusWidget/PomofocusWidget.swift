import AppIntents
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
        (try? PomofocusWidgetSnapshotStore.load()) ?? .idle
    }
}

/// The widget's colours: the app's chosen theme when it has shared one, otherwise the
/// original graphite and gold.
private struct WidgetPalette {
    let isDark: Bool
    let black: Color
    let white: Color
    let secondary: Color
    let track: Color
    let gold: Color

    init(_ theme: PomofocusWidgetTheme?) {
        guard let theme else {
            isDark = true
            black = Color(red: 0.025, green: 0.028, blue: 0.032)
            white = Color(red: 0.945, green: 0.937, blue: 0.914)
            secondary = Color(red: 0.56, green: 0.58, blue: 0.61)
            track = Color.white.opacity(0.11)
            gold = Color(red: 0.741, green: 0.647, blue: 0.435)
            return
        }
        isDark = theme.isDark
        black = Self.color(theme.background)
        white = Self.color(theme.ink)
        secondary = Self.color(theme.secondaryInk)
        track = Self.color(theme.line)
        gold = Self.color(theme.accent)
    }

    private static func color(_ hex: String) -> Color {
        var value: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)).scanHexInt64(&value)
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}

private struct PomofocusWidgetView: View {
    let entry: PomofocusEntry
    @Environment(\.widgetFamily) private var family
    private var palette: WidgetPalette { WidgetPalette(entry.snapshot.theme) }

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
        .containerBackground(for: .widget) { palette.black }
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
        .widgetURL(URL(string: "pomofocus://focus"))
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                WidgetMark(palette: palette, size: 18)
                Text(entry.snapshot.phase.compactTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.white)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 6)
            timerText(size: 34)
            Spacer(minLength: 6)
            WidgetControlRow(actions: WidgetAction.actions(for: entry.snapshot), palette: palette, compact: true, short: true)
                .padding(.bottom, 10)
            ProgressBand(palette: palette, snapshot: entry.snapshot)
        }
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        WidgetMark(palette: palette, size: 17)
                        Text(entry.snapshot.phase.compactTitle)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    timerText(size: 38)
                    WidgetControlRow(actions: WidgetAction.actions(for: entry.snapshot), palette: palette, compact: true, short: true)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.snapshot.taskName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.white)
                        .lineLimit(1)
                    if !entry.snapshot.intention.isEmpty {
                        Text(entry.snapshot.intention)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Text("Block \(entry.snapshot.cycleCurrent) of \(entry.snapshot.cycleTotal)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            ProgressBand(palette: palette, snapshot: entry.snapshot)
        }
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                WidgetMark(palette: palette, size: 19)
                Text("Pomofocus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.white)
                Spacer()
                Text(entry.snapshot.status.compactTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 20)

            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    timerText(size: 50)
                    Text(entry.snapshot.phase.compactTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 7) {
                    Text(entry.snapshot.taskName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(palette.white)
                        .lineLimit(1)
                    if !entry.snapshot.intention.isEmpty {
                        Text(entry.snapshot.intention)
                            .font(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                    }
                    Text("Block \(entry.snapshot.cycleCurrent) of \(entry.snapshot.cycleTotal)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .padding(.top, 5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 16)

            WidgetControlRow(actions: WidgetAction.actions(for: entry.snapshot), palette: palette, compact: false)

            Spacer(minLength: 16)

            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                Spacer()
                Text(durationString(entry.snapshot.todayFocusSeconds))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(palette.white)
            }
            .padding(.bottom, 9)

            ProgressBand(palette: palette, snapshot: entry.snapshot)
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
        .foregroundStyle(palette.white)
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
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

/// One widget button: what it says, and the intent it runs.
struct WidgetAction {
    let title: String
    let icon: String
    let intent: any AppIntent
    let prominent: Bool
    /// For the small and medium sizes, where "Next: 25 min focus" won't fit.
    var shortTitle: String?

    /// The same choices as the menu bar panel, picked from the widget's last snapshot. The
    /// app double-checks each one against its live state before acting.
    static func actions(for snapshot: PomofocusWidgetSnapshot) -> [WidgetAction] {
        let secondary = snapshot.phase == .focus
            ? WidgetAction(title: "End", icon: "stop.fill", intent: EndSessionIntent(), prominent: false)
            : WidgetAction(title: "Skip break", icon: "forward.end.fill", intent: SkipBreakIntent(), prominent: false)
        if snapshot.status == .breathing {
            return [WidgetAction(title: "Skip breaths", icon: "forward.fill", intent: NextBlockIntent(), prominent: true, shortTitle: "Skip"),
                    WidgetAction(title: "Cancel", icon: "xmark", intent: EndSessionIntent(), prominent: false)]
        }
        if let next = snapshot.nextTitle {
            let end = WidgetAction(title: "End", icon: "stop.fill", intent: EndSessionIntent(), prominent: false)
            return [WidgetAction(title: next, icon: "arrow.right", intent: NextBlockIntent(), prominent: true, shortTitle: "Next"), end]
        }
        switch snapshot.status {
        case .idle, .completed, .breathing:
            return [WidgetAction(title: snapshot.phase == .focus ? "Start focus" : "Start break", icon: "play.fill",
                                 intent: StartTimerIntent(), prominent: true, shortTitle: "Start")]
        case .running, .overtime:
            return [WidgetAction(title: "Pause", icon: "pause.fill", intent: PauseTimerIntent(), prominent: true), secondary]
        case .paused:
            return [WidgetAction(title: "Resume", icon: "play.fill", intent: ResumeTimerIntent(), prominent: true), secondary]
        }
    }
}

/// The main action as a filled capsule, and the other as a quiet one beside it. In the
/// smaller sizes the second button shows only its symbol.
private struct WidgetControlRow: View {
    let actions: [WidgetAction]
    let palette: WidgetPalette
    let compact: Bool
    var short = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                button(action)
            }
            if compact { Spacer(minLength: 0) }
        }
    }

    private func button(_ action: WidgetAction) -> some View {
        let iconOnly = compact && !action.prominent
        return Button(intent: action.intent) {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
                if !iconOnly {
                    Text(short ? action.shortTitle ?? action.title : action.title)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(action.prominent ? palette.black : palette.white)
            .padding(.horizontal, iconOnly ? 0 : (compact ? 10 : 14))
            .frame(width: iconOnly ? 26 : nil, height: compact ? 26 : 30)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(action.prominent ? palette.gold : palette.track, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}

private struct ProgressBand: View {
    let palette: WidgetPalette
    let snapshot: PomofocusWidgetSnapshot

    var body: some View {
        Group {
            if snapshot.status == .running,
               let endDate = snapshot.endDate {
                let startDate = endDate.addingTimeInterval(TimeInterval(-snapshot.plannedSeconds))
                // Without empty labels macOS prints the countdown a second time under the bar.
                ProgressView(timerInterval: startDate...endDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
            } else {
                ProgressView(value: max(0, min(1, 1 - snapshot.progress)))
            }
        }
        .progressViewStyle(.linear)
        .tint(palette.gold)
        .background(palette.track)
        .clipShape(Capsule())
        .frame(height: 3)
    }
}

private struct WidgetMark: View {
    let palette: WidgetPalette
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.07, to: 0.93)
                .stroke(palette.white, style: StrokeStyle(lineWidth: 2.1, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Capsule()
                .fill(palette.white)
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
        if #available(macOS 26.0, *) {
            TimerControl()
            EndSessionControl()
        }
    }
}
