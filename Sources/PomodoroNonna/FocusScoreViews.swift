import SwiftUI

// MARK: - Ring

/// The score as a three-quarter ring with the number in the middle.
struct FocusScoreRing: View {
    let score: Int?
    var size: CGFloat = 132
    var lineWidth: CGFloat = 11
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = 0.0

    private let sweep = 0.75

    var body: some View {
        let fraction = Double(score ?? 0) / 100
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(NonnaTheme.line, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: sweep * shown)
                .stroke(
                    AngularGradient(colors: [NonnaTheme.terracotta.opacity(0.55), NonnaTheme.terracotta],
                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(135))
                .shadow(color: NonnaTheme.terracotta.opacity(0.3), radius: 6)
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "–")
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of 100")
                    .font(.system(size: max(9, size * 0.075), weight: .medium))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .frame(width: size, height: size)
        .onAppear { animate(to: fraction) }
        .onChange(of: score) { _, _ in animate(to: fraction) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(score.map { "Focus score \($0) out of 100" } ?? "No focus score yet")
    }

    private func animate(to fraction: Double) {
        if reduceMotion { shown = fraction; return }
        withAnimation(.spring(duration: 0.9, bounce: 0.1)) { shown = fraction }
    }
}

// MARK: - Dashboard card

/// Today's score on the dashboard, with the week beside it. Click to see why.
struct FocusScoreCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @State private var showsDetail = false
    @State private var hovering = false

    var body: some View {
        let week = model.focusScoreHistory(days: 7)
        let today = week.last?.score
        let previous = week.dropLast().compactMap(\.score)
        let average = previous.isEmpty ? nil : previous.reduce(0) { $0 + $1.total } / previous.count

        Button {
            // Open without the card's hover animation leaking into the sheet's first layout.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { showsDetail = true }
        } label: {
            NonnaCard(padding: 22) {
                HStack(alignment: .center, spacing: 26) {
                    FocusScoreRing(score: today?.total, size: compact ? 112 : 132)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Focus score, today")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(NonnaTheme.terracotta)
                        Text(today?.label ?? "No score yet")
                            .font(.system(size: 24, weight: .semibold))
                        Group {
                            if let today, let average {
                                let delta = today.total - average
                                Label(delta == 0 ? "Right on your 7-day average" : "\(abs(delta)) \(delta > 0 ? "above" : "below") your 7-day average of \(average)",
                                      systemImage: delta > 0 ? "arrow.up.right" : delta < 0 ? "arrow.down.right" : "equal")
                            } else if today == nil {
                                if let last = week.last(where: { $0.score != nil }), let lastScore = last.score {
                                    Text("Last score: \(lastScore.total) on \(last.day.formatted(.dateTime.weekday(.wide))). Start a block to get today's.")
                                } else {
                                    Text("Start a focus block to get today's score.")
                                }
                            } else if let weakest = today?.weakest {
                                Text(weakest.tip)
                            }
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        HStack(spacing: 4) {
                            Text("See why")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(hovering ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                    }

                    Spacer(minLength: 12)

                    if !compact {
                        WeekScoreBars(week: week)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hovering ? NonnaTheme.terracotta.opacity(0.45) : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .sheet(isPresented: $showsDetail) {
            FocusScoreDetail(initialDay: Self.latestScoredDay(model)) { showsDetail = false }
                .environment(model)
                .closesOnClickOutside { showsDetail = false }
        }
    }
}

extension FocusScoreCard {
    /// Today if it has a score, otherwise the latest day that does, so the sheet never opens empty.
    @MainActor static func latestScoredDay(_ model: AppModel) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        if model.focusScore(on: today) != nil { return today }
        return model.focusScoreHistory(days: 14).last(where: { $0.score != nil })?.day ?? today
    }
}

/// Seven small bars, one per day, today on the right.
private struct WeekScoreBars: View {
    let week: [(day: Date, score: FocusScore?)]
    var selected: Date?
    var height: CGFloat = 76
    var onSelect: ((Date) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            ForEach(week, id: \.day) { entry in
                let isToday = Calendar.current.isDateInToday(entry.day)
                let isSelected = selected.map { Calendar.current.isDate($0, inSameDayAs: entry.day) } ?? isToday
                VStack(spacing: 6) {
                    Text(entry.score.map { "\($0.total)" } ?? "")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(entry.score == nil ? NonnaTheme.line : NonnaTheme.terracotta.opacity(isSelected ? 1 : 0.45))
                        .frame(width: 16, height: max(4, height * Double(entry.score?.total ?? 0) / 100))
                    Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                }
                .frame(height: height + 34, alignment: .bottom)
                .contentShape(Rectangle())
                .onTapGesture { onSelect?(entry.day) }
                .help(entry.score.map { "\(entry.day.formatted(.dateTime.weekday(.wide))): \($0.total), \($0.label.lowercased())" } ?? "No blocks that day")
            }
        }
    }
}

// MARK: - Detail

/// "Why is my score 72?": each part, what happened, and what would lift it.
struct FocusScoreDetail: View {
    @Environment(AppModel.self) private var model
    let onDone: () -> Void
    @State private var day: Date

    /// Opens on `initialDay`, decided before the sheet appears so it lays out once.
    init(initialDay: Date, onDone: @escaping () -> Void) {
        _day = State(initialValue: initialDay)
        self.onDone = onDone
    }

    var body: some View {
        let history = model.focusScoreHistory(days: 14)
        let score = model.focusScore(on: day)
        let isToday = Calendar.current.isDateInToday(day)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Focus score")
                        .font(.system(size: 26, weight: .regular, design: .serif))
                    Spacer()
                    Button("Done", action: onDone)
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                        .keyboardShortcut(.cancelAction)
                }

                HStack(alignment: .center, spacing: 26) {
                    FocusScoreRing(score: score?.total, size: 150, lineWidth: 13)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                                .buttonStyle(.plain)
                            Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                                .font(.system(size: 13, weight: .semibold))
                            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.plain)
                                .disabled(isToday)
                                .opacity(isToday ? 0.3 : 1)
                        }
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        Text(score?.label ?? "No blocks this day")
                            .font(.system(size: 24, weight: .semibold))
                        if let weakest = score?.weakest, weakest.fraction < 0.95 {
                            Label {
                                Text("Biggest lift: \(weakest.title.lowercased()). \(weakest.tip)")
                            } icon: {
                                Image(systemName: "arrow.up.forward")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                        } else if score == nil {
                            Text(isToday ? "Start a focus block and your score builds as you go." : "Nothing was started this day.")
                                .font(.system(size: 12))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                        }
                    }
                }

                if let score {
                    VStack(spacing: 10) {
                        ForEach(score.parts) { part in
                            PartRow(part: part)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Last 14 days")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    WeekScoreBars(week: history, selected: day, height: 60) { picked in
                        day = Calendar.current.startOfDay(for: picked)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("How it's worked out")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Up to 40 points for time focused against your daily goal (overtime past 15 minutes doesn't count), 25 for finishing the blocks you start, 15 for few pauses, 10 for breaks taken and back on time, and 10 for your longest unbroken stretch. It's a mirror for your own habits, not a clinical measure.")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
        }
        .frame(width: 600)
        .frame(minHeight: 420, idealHeight: 640, maxHeight: 720)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
    }

    private func shift(_ days: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: day),
              next <= Calendar.current.startOfDay(for: Date()) else { return }
        day = next
    }
}

private struct PartRow: View {
    let part: FocusScore.Part

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.terracotta)
                    .frame(width: 18)
                Text(part.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(part.points.rounded())) / \(Int(part.maxPoints))")
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(NonnaTheme.line)
                    Capsule()
                        .fill(NonnaTheme.terracotta.opacity(0.35 + 0.65 * part.fraction))
                        .frame(width: geometry.size.width * part.fraction)
                }
            }
            .frame(height: 5)
            Text(part.detail)
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(14)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private var icon: String {
        switch part.kind {
        case .time: "clock"
        case .followThrough: "checkmark.circle"
        case .interruptions: "hand.raised"
        case .breaks: "cup.and.saucer"
        case .depth: "water.waves"
        }
    }
}

// MARK: - Runaway cleanup

/// Offers to trim timers that ran for hours while nobody was there.
struct RunawayTimersBanner: View {
    @Environment(AppModel.self) private var model
    @State private var confirming = false

    var body: some View {
        let count = model.runawayTimerCount
        if count > 0 {
            HStack(spacing: 14) {
                Image(systemName: "hourglass.badge.plus")
                    .font(.system(size: 18))
                    .foregroundStyle(NonnaTheme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) \(count == 1 ? "timer" : "timers") kept running for over an hour")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Probably while you were away. They inflate your overtime and totals.")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button("Trim to planned time") { confirming = true }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            .padding(14)
            .background(NonnaTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.gold.opacity(0.4), lineWidth: 0.8) }
            .confirmationDialog("Trim \(count) \(count == 1 ? "timer" : "timers") back to their planned length?", isPresented: $confirming) {
                Button("Trim \(count)") { model.trimRunawayTimers() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each one keeps its planned time; the hours after that are removed. This can't be undone.")
            }
        }
    }
}
