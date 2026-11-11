import SwiftUI

enum WeekPrompt {
    /// The start of the last week whose summary was opened or dismissed.
    static let seenKey = "week.seenStart"
}

extension AppModel {
    /// Every focused piece of a session, for the weekly summary.
    var weekBlocks: [WeekSummary.Block] {
        sessions.filter { $0.outcome != .abandoned && $0.focusedSeconds > 0 }
            .map { WeekSummary.Block(start: $0.startedAt, seconds: $0.focusedSeconds, list: $0.taskName) }
    }

    func weekSummary(startingAt start: Date) -> WeekSummary {
        WeekSummary.calculate(blocks: weekBlocks, checkIns: moodCheckIns, weekStart: start)
    }

    var lastWeekStart: Date {
        let calendar = Calendar.current
        let thisWeek = WeekSummary.weekStart(containing: Date(), calendar: calendar)
        return calendar.date(byAdding: .day, value: -7, to: thisWeek) ?? thisWeek
    }
}

// MARK: - Banner

/// At the start of a week, once: last week is ready to look back on. Only when there was
/// some focus last week; an empty week isn't pointed out.
struct WeekReadyBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(WeekPrompt.seenKey) private var seenStart = 0.0

    var body: some View {
        let start = model.lastWeekStart
        if model.status == .idle, seenStart != start.timeIntervalSinceReferenceDate, model.weekSummary(startingAt: start).hasFocus {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Your week in focus is ready")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Take a look") {
                    model.weekSheetStart = start
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) { seenStart = start.timeIntervalSinceReferenceDate }
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
                Button {
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) { seenStart = start.timeIntervalSinceReferenceDate }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.secondaryInk)
                .help("Not now. It's always on the Dashboard")
                .accessibilityLabel("Not now")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NonnaTheme.pane(NonnaTheme.raisedPaper, 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
            .transition(.banner(reduceMotion: reduceMotion))
        }
    }
}

// MARK: - Dashboard row

/// A line at the top of the Dashboard: last week in a sentence, and the way in.
struct WeekDashboardRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.weekSummary(startingAt: model.lastWeekStart)
        NonnaCard(padding: 18) {
            HStack(spacing: 14) {
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(NonnaTheme.terracotta)
                    .frame(width: 34, height: 34)
                    .background(NonnaTheme.terracotta.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your week")
                        .font(.system(size: 15, weight: .semibold))
                    Text(summary.hasFocus
                         ? "Last week: \(summary.totalSeconds.focusDurationString) across \(summary.daysFocused == 1 ? "one day" : "\(summary.daysFocused) days")."
                         : "A look back at each week, with one suggestion for the next.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button("Open") { model.weekSheetStart = model.lastWeekStart }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
        }
    }
}

// MARK: - The week

struct WeekSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let initialStart: Date
    let onClose: () -> Void
    @State private var start: Date?

    private var weekStart: Date { start ?? initialStart }
    private var isThisWeek: Bool {
        weekStart == WeekSummary.weekStart(containing: Date(), calendar: .current)
    }

    var body: some View {
        let summary = model.weekSummary(startingAt: weekStart)
        VStack(spacing: 0) {
            header(summary)
            ScrollView {
                VStack(spacing: 22) {
                    headline(summary)
                    dayBars(summary)
                    tiles(summary)
                    suggestion(summary)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
        }
        .frame(width: 600, height: 730)
        .background(NonnaTheme.cream)
        .animation(reduceMotion ? nil : NonnaMotion.settle, value: weekStart)
    }

    private func header(_ summary: WeekSummary) -> some View {
        HStack(spacing: 10) {
            Button { move(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .help("The week before")
                .accessibilityLabel("The week before")
            VStack(spacing: 2) {
                Text(isThisWeek ? "This week so far" : "Your week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NonnaTheme.terracotta)
                Text(rangeText(summary))
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            Button { move(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(isThisWeek)
                .opacity(isThisWeek ? 0.3 : 1)
                .help("The week after")
                .accessibilityLabel("The week after")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(NonnaTheme.secondaryInk)
        .padding(.horizontal, 30)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private func move(_ weeks: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: 7 * weeks, to: weekStart) else { return }
        start = next
    }

    private func rangeText(_ summary: WeekSummary) -> String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: summary.end) ?? summary.end
        return (summary.start..<last).formatted(.interval.month(.abbreviated).day())
    }

    private func headline(_ summary: WeekSummary) -> some View {
        VStack(spacing: 8) {
            Text(summary.totalSeconds.focusDurationString)
                .font(.system(size: 56, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(comparison(summary))
                .font(.system(size: 13))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(.top, 8)
    }

    private func comparison(_ summary: WeekSummary) -> String {
        let blocks = "\(summary.blockCount) \(summary.blockCount == 1 ? "block" : "blocks")"
        guard summary.previousSeconds > 0 else { return "of focus, in \(blocks)" }
        let change = summary.totalSeconds - summary.previousSeconds
        if abs(change) < 600 { return "of focus in \(blocks), about the same as the week before" }
        return change > 0
            ? "of focus in \(blocks), \(change.focusDurationString) more than the week before"
            : "of focus in \(blocks), a lighter week than the one before"
    }

    private func dayBars(_ summary: WeekSummary) -> some View {
        let most = max(1, summary.days.map(\.seconds).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 14) {
            ForEach(summary.days) { day in
                VStack(spacing: 6) {
                    Capsule()
                        .fill(day.seconds > 0 ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                        .frame(width: 26, height: max(6, 80 * CGFloat(day.seconds) / CGFloat(most)))
                    Text(day.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                .help("\(day.day.formatted(.dateTime.weekday(.wide))): \(day.seconds.focusDurationString)")
                .accessibilityElement()
                .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide)))
                .accessibilityValue(day.seconds.focusDurationString)
            }
        }
        .frame(height: 104, alignment: .bottom)
    }

    private func tiles(_ summary: WeekSummary) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Best day", value: summary.bestDay.map { $0.day.formatted(.dateTime.weekday(.wide)) } ?? "None yet",
                     detail: summary.bestDay.map { $0.seconds.focusDurationString } ?? "")
                tile("Best time", value: summary.bestTime.map { $0.rawValue.capitalized } ?? "None yet",
                     detail: summary.bestTime == nil ? "" : "\(Int((summary.bestTimeShare * 100).rounded()))% of your focus")
            }
            GridRow {
                tile("Most time on", value: summary.topList?.name ?? "No list",
                     detail: summary.topList.map { $0.seconds.focusDurationString } ?? "")
                moodTile(summary)
            }
        }
    }

    private func tile(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
            Text(detail.isEmpty ? " " : detail)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private func moodTile(_ summary: WeekSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Mood")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Text(summary.moodAverage.map { MoodColor.tone($0) } ?? "No check-ins")
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(summary.moodCheckIns == 0 ? " " : "\(summary.moodCheckIns) \(summary.moodCheckIns == 1 ? "check-in" : "check-ins")")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 0)
            if let average = summary.moodAverage {
                MoodBloom(valence: (average - 1) / 6, turning: false)
                    .frame(width: 38, height: 38)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private func suggestion(_ summary: WeekSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb")
                .foregroundStyle(NonnaTheme.terracotta)
            VStack(alignment: .leading, spacing: 4) {
                Text(isThisWeek ? "So far" : "For next week")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Text(summary.suggestion)
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(NonnaTheme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
