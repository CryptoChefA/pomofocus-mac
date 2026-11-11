import AppKit
import SwiftUI

enum YearPrompt {
    /// The last year whose wrap-up banner was opened or dismissed.
    static let seenKey = "year.seenYear"
}

extension AppModel {
    func yearReplay(_ year: Int) -> YearReplay {
        YearReplay.calculate(blocks: weekBlocks, checkIns: moodCheckIns, year: year)
    }

    /// The finished year in December and early January, otherwise this year so far.
    var replayYearNow: Int {
        YearReplay.wrapUpYear(for: Date()) ?? Calendar.current.component(.year, from: Date())
    }
}

extension Int {
    /// "212 hours" once the total is large, "3h 20m" below ten hours.
    var yearHoursString: String {
        let hours = self / 3600
        return hours >= 10 ? "\(hours) hours" : focusDurationString
    }
}

// MARK: - Ways in

/// In December and early January, once: the year is ready to look back on.
struct YearReadyBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(YearPrompt.seenKey) private var seenYear = 0

    var body: some View {
        if model.status == .idle, let year = YearReplay.wrapUpYear(for: Date()), seenYear != year,
           model.yearReplay(year).hasFocus {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(NonnaTheme.terracotta)
                Text("Your \(String(year)) in focus is ready")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Take a look") {
                    model.yearSheet = year
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) { seenYear = year }
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
                Button {
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) { seenYear = year }
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

/// A line on the Dashboard under Your week.
struct YearDashboardRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let year = model.replayYearNow
        let replay = model.yearReplay(year)
        let finished = YearReplay.wrapUpYear(for: Date()) != nil
        NonnaCard(padding: 18) {
            HStack(spacing: 14) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 16))
                    .foregroundStyle(NonnaTheme.terracotta)
                    .frame(width: 34, height: 34)
                    .background(NonnaTheme.terracotta.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(finished ? "Your \(String(year)) in focus" : "Your year so far")
                        .font(.system(size: 15, weight: .semibold))
                    Text(replay.hasFocus
                         ? "\(replay.totalSeconds.yearHoursString) of focus across \(replay.daysFocused == 1 ? "one day" : "\(replay.daysFocused) days") this year."
                         : "Your year in focus fills in as you go.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button("Open") { model.yearSheet = year }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
        }
    }
}

// MARK: - The story

private enum YearCard: Hashable {
    case intro, total, months, lists, rhythm, streak, moods, share, empty

    static func cards(for replay: YearReplay) -> [YearCard] {
        guard replay.hasFocus else { return [.empty] }
        var cards: [YearCard] = [.intro, .total, .months]
        if !replay.topLists.isEmpty { cards.append(.lists) }
        cards.append(.rhythm)
        cards.append(.streak)
        if replay.hasMoods { cards.append(.moods) }
        cards.append(.share)
        return cards
    }
}

/// The year as a few full cards. Click, or press the arrow keys or space, to move through
/// them; the segments at the top show where you are.
struct YearSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let year: Int
    let onClose: () -> Void
    @State private var index = 0
    @State private var forward = true
    @FocusState private var focused: Bool

    var body: some View {
        let replay = model.yearReplay(year)
        let cards = YearCard.cards(for: replay)
        let card = cards[min(index, cards.count - 1)]
        ZStack(alignment: .top) {
            YearCardBackground(card: card)
            GeometryReader { proxy in
                YearCardView(card: card, replay: replay, finished: YearReplay.wrapUpYear(for: Date()) == year || year < Calendar.current.component(.year, from: Date()))
                    .id(card)
                    .transition(transition)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        move(point.x < proxy.size.width * 0.3 ? -1 : 1, count: cards.count)
                    }
            }
            .padding(.top, 44)
            .padding(.bottom, 52)
            header(count: cards.count)
            footer(count: cards.count)
        }
        .frame(width: 560, height: 720)
        .foregroundStyle(NonnaTheme.ink)
        .background(NonnaTheme.cream)
        .environment(\.colorScheme, NonnaTheme.colorScheme)
        .clipped()
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { move(1, count: cards.count); return .handled }
        .onKeyPress(.space) { move(1, count: cards.count); return .handled }
        .onKeyPress(.leftArrow) { move(-1, count: cards.count); return .handled }
        .onAppear { focused = true }
    }

    private var transition: AnyTransition {
        reduceMotion ? .opacity : .push(from: forward ? .trailing : .leading).combined(with: .opacity)
    }

    private func move(_ step: Int, count: Int) {
        let next = index + step
        guard next >= 0 else { return }
        guard next < count else { onClose(); return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : NonnaMotion.settle) { index = next }
    }

    /// One segment per card, filled up to the current one.
    private func header(count: Int) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? NonnaTheme.ink.opacity(0.75) : NonnaTheme.ink.opacity(0.14))
                        .frame(height: 3)
                }
            }
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: index)
            .accessibilityElement()
            .accessibilityLabel("Card \(index + 1) of \(count)")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(NonnaTheme.secondaryInk)
            .keyboardShortcut(.cancelAction)
            .help("Close")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private func footer(count: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Button { move(-1, count: count) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain)
                    .opacity(index == 0 ? 0 : 1)
                    .disabled(index == 0)
                    .help("Back")
                    .accessibilityLabel("Back")
                Spacer()
                Text(index == 0 && count > 1 ? "Click or press → to keep going" : " ")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                Spacer()
                Button { move(1, count: count) } label: {
                    Image(systemName: index == count - 1 ? "checkmark" : "chevron.right")
                }
                .buttonStyle(.plain)
                .help(index == count - 1 ? "Done" : "Next")
                .accessibilityLabel(index == count - 1 ? "Done" : "Next")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// A soft glow of the theme's accent that drifts to a new place on each card.
private struct YearCardBackground: View {
    let card: YearCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var spot: UnitPoint {
        switch card {
        case .intro, .empty: UnitPoint(x: 0.5, y: 0.35)
        case .total: UnitPoint(x: 0.2, y: 0.25)
        case .months: UnitPoint(x: 0.8, y: 0.7)
        case .lists: UnitPoint(x: 0.15, y: 0.6)
        case .rhythm: UnitPoint(x: 0.85, y: 0.2)
        case .streak: UnitPoint(x: 0.3, y: 0.8)
        case .moods: UnitPoint(x: 0.7, y: 0.4)
        case .share: UnitPoint(x: 0.5, y: 0.55)
        }
    }

    var body: some View {
        RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.2), NonnaTheme.terracotta.opacity(0)],
                       center: spot, startRadius: 0, endRadius: 360)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: card)
            .allowsHitTesting(false)
    }
}

// MARK: - Cards

private struct YearCardView: View {
    let card: YearCard
    let replay: YearReplay
    let finished: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            switch card {
            case .intro: intro
            case .total: total
            case .months: months
            case .lists: lists
            case .rhythm: rhythm
            case .streak: streak
            case .moods: moods
            case .share: YearShareCard(replay: replay, finished: finished)
            case .empty: empty
            }
        }
        .padding(.horizontal, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.7, bounce: 0.12).delay(0.12)) { shown = true }
        }
    }

    /// Each line rises into place a moment after the one before.
    private func reveal(_ step: Int) -> some ViewModifier {
        RevealModifier(shown: shown, delay: reduceMotion ? 0 : Double(step) * 0.12, distance: reduceMotion ? 0 : 14)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(NonnaTheme.terracotta)
    }

    private func big(_ text: String, size: CGFloat = 64) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var intro: some View {
        VStack(spacing: 16) {
            label(finished ? "Your year in focus" : "Your year so far").modifier(reveal(0))
            big(String(replay.year), size: 112).modifier(reveal(1))
            line(introLine).modifier(reveal(2))
        }
    }

    private var introLine: String {
        let calendar = Calendar.current
        if let first = replay.firstBlock, calendar.component(.month, from: first) > 1 {
            let since = first.formatted(.dateTime.day().month(.wide))
            return finished ? "From your first block on \(since) to the end of the year." : "From your first block on \(since) to today."
        }
        return finished ? "Every block, from January to December." : "Every block, from January to today."
    }

    private var total: some View {
        VStack(spacing: 14) {
            label("You focused for").modifier(reveal(0))
            big(replay.totalSeconds.yearHoursString, size: 80).modifier(reveal(1))
            line("in \(replay.blockCount) \(replay.blockCount == 1 ? "block" : "blocks"), across \(replay.daysFocused == 1 ? "one day" : "\(replay.daysFocused) days").")
                .modifier(reveal(2))
            if let scale = replay.scale {
                line(scale).padding(.top, 10).modifier(reveal(3))
            }
        }
    }

    private var months: some View {
        let most = max(1, replay.months.map(\.seconds).max() ?? 1)
        let best = replay.bestMonth?.month
        return VStack(spacing: 18) {
            label("Month by month").modifier(reveal(0))
            if let bestMonth = replay.bestMonth {
                big("\(bestMonth.month.formatted(.dateTime.month(.wide))) was your biggest month", size: 34)
                    .modifier(reveal(1))
                line("\(bestMonth.seconds.focusDurationString) of focus.").modifier(reveal(2))
            }
            HStack(alignment: .bottom, spacing: 9) {
                ForEach(Array(replay.months.enumerated()), id: \.offset) { i, month in
                    VStack(spacing: 7) {
                        Capsule()
                            .fill(month.month == best ? NonnaTheme.terracotta
                                  : month.seconds > 0 ? NonnaTheme.terracotta.opacity(0.35) : NonnaTheme.strongLine)
                            .frame(width: 22, height: shown ? max(5, 150 * CGFloat(month.seconds) / CGFloat(most)) : 5)
                            .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.15).delay(0.3 + Double(i) * 0.04), value: shown)
                        Text(month.month.formatted(.dateTime.month(.narrow)))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(month.month == best ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                    }
                    .help("\(month.month.formatted(.dateTime.month(.wide))): \(month.seconds.focusDurationString)")
                    .accessibilityElement()
                    .accessibilityLabel(month.month.formatted(.dateTime.month(.wide)))
                    .accessibilityValue(month.seconds.focusDurationString)
                }
            }
            .frame(height: 176, alignment: .bottom)
            .padding(.top, 14)
        }
    }

    private var lists: some View {
        let most = max(1, replay.topLists.first?.seconds ?? 1)
        return VStack(spacing: 18) {
            label("Where your time went").modifier(reveal(0))
            if let top = replay.topLists.first {
                big("Most of it went to \(top.name)", size: 34).modifier(reveal(1))
            }
            VStack(spacing: 12) {
                ForEach(Array(replay.topLists.enumerated()), id: \.offset) { i, list in
                    HStack(spacing: 14) {
                        Text("\(i + 1)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(i == 0 ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(list.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                                Text(list.seconds.focusDurationString)
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                            }
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(i == 0 ? NonnaTheme.terracotta : NonnaTheme.terracotta.opacity(0.35))
                                    .frame(width: shown ? max(6, proxy.size.width * CGFloat(list.seconds) / CGFloat(most)) : 6)
                                    .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.1).delay(0.35 + Double(i) * 0.1), value: shown)
                            }
                            .frame(height: 6)
                        }
                    }
                    .padding(14)
                    .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                    .modifier(reveal(2 + i))
                }
            }
            .padding(.top, 8)
            if replay.listCount > replay.topLists.count {
                line("Out of \(replay.listCount) lists in all.").modifier(reveal(5))
            }
        }
    }

    private var rhythm: some View {
        let parts: [(WeekSummary.TimeOfDay, String, String)] = [
            (.morning, "Morning", "sunrise"), (.afternoon, "Afternoon", "sun.max"), (.evening, "Evening", "moon"),
        ]
        return VStack(spacing: 18) {
            label("Your rhythm").modifier(reveal(0))
            big(rhythmTitle, size: 40).modifier(reveal(1))
            line(replay.rhythm).modifier(reveal(2))
            HStack(spacing: 10) {
                ForEach(parts, id: \.0) { time, name, icon in
                    let share = replay.timeShares[time] ?? 0
                    VStack(spacing: 6) {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundStyle(time == replay.bestTime ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                        Text("\(Int((share * 100).rounded()))%")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(time == replay.bestTime ? NonnaTheme.terracotta.opacity(0.1) : NonnaTheme.paper,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                }
            }
            .padding(.top, 8)
            .modifier(reveal(3))
            if let day = replay.bestDay {
                line("Your biggest day was \(day.day.formatted(.dateTime.weekday(.wide).day().month(.wide))), with \(day.seconds.focusDurationString).")
                    .padding(.top, 6)
                    .modifier(reveal(4))
            }
        }
    }

    private var rhythmTitle: String {
        guard let time = replay.bestTime, (replay.timeShares[time] ?? 0) >= 0.45 else { return "All through the day" }
        switch time {
        case .morning: return "Mornings"
        case .afternoon: return "Afternoons"
        case .evening: return "Evenings"
        }
    }

    private var streak: some View {
        VStack(spacing: 14) {
            label("Showing up").modifier(reveal(0))
            big(replay.longestStreak == 1 ? "1 day" : "\(replay.longestStreak) days in a row", size: replay.longestStreak == 1 ? 80 : 56)
                .modifier(reveal(1))
            if let end = replay.streakEnd, replay.longestStreak > 1 {
                line("Your longest streak, ending \(end.formatted(.dateTime.day().month(.wide))).").modifier(reveal(2))
            } else {
                line("Your longest streak so far. Two days in a row is a good next goal.").modifier(reveal(2))
            }
            if let block = replay.longestBlock {
                VStack(spacing: 4) {
                    Text("Longest single block")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                    Text(block.seconds.focusDurationString)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(block.start.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                .frame(maxWidth: 260)
                .padding(18)
                .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                .padding(.top, 18)
                .modifier(reveal(3))
            }
        }
    }

    private var moods: some View {
        let average = replay.moodAverage ?? 4
        let segments: [(Double, Double)] = [(replay.moodMix.unpleasant, 2), (replay.moodMix.neutral, 4), (replay.moodMix.pleasant, 6)]
        return VStack(spacing: 16) {
            label("How it felt").modifier(reveal(0))
            MoodBloom(valence: (average - 1) / 6)
                .frame(width: 120, height: 120)
                .modifier(reveal(1))
            big(MoodColor.tone(average), size: 36).modifier(reveal(2))
            line("Across \(replay.moodCount) check-ins.").modifier(reveal(2))
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        if segment.0 > 0 {
                            Capsule()
                                .fill(MoodColor.color(segment.1))
                                .frame(width: max(8, (proxy.size.width - 6) * segment.0))
                        }
                    }
                }
            }
            .frame(height: 10)
            .padding(.top, 4)
            .modifier(reveal(3))
            HStack {
                Text("Unpleasant \(Int((replay.moodMix.unpleasant * 100).rounded()))%")
                Spacer()
                Text("Pleasant \(Int((replay.moodMix.pleasant * 100).rounded()))%")
            }
            .font(.system(size: 11))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .modifier(reveal(3))
            if !replay.topFeelings.isEmpty {
                line("The words you reached for most: \(ListFormatter.localizedString(byJoining: replay.topFeelings)).")
                    .padding(.top, 6)
                    .modifier(reveal(4))
            }
            if let month = replay.brightestMonth {
                line("\(month.formatted(.dateTime.month(.wide))) felt the brightest.").modifier(reveal(5))
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            label("Your year in focus").modifier(reveal(0))
            big(String(replay.year), size: 96).modifier(reveal(1))
            line("This fills in as you go. Finish a block or two and it'll show your hours, your best month and your rhythm.")
                .modifier(reveal(2))
        }
    }
}

private struct RevealModifier: ViewModifier {
    let shown: Bool
    let delay: Double
    let distance: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : distance)
            .animation(.spring(duration: 0.7, bounce: 0.1).delay(delay), value: shown)
    }
}

// MARK: - Sharing

/// The last card: the image to share, and what's on it.
private struct YearShareCard: View {
    let replay: YearReplay
    let finished: Bool
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Share your year")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            YearShareImage(replay: replay, finished: finished)
                .frame(width: 288, height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            HStack(spacing: 10) {
                Button("Save Image…") { save() }
                    .buttonStyle(NonnaButtonStyle())
                Button(copied ? "Copied" : "Copy") { copy() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            .padding(.top, 4)
            Text("Only the numbers go on the image. Your list names and moods stay on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .multilineTextAlignment(.center)
        }
    }

    @MainActor private func render() -> NSImage? {
        let renderer = ImageRenderer(content: YearShareImage(replay: replay, finished: finished).frame(width: 360, height: 450))
        renderer.scale = 3   // 1080 by 1350, the size most places expect for a tall post
        return renderer.nsImage
    }

    @MainActor private func save() {
        guard let image = render(), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "My \(String(replay.year)) in focus.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? png.write(to: url)
        }
    }

    @MainActor private func copy() {
        guard let image = render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
    }
}

/// The shareable picture, drawn at 360 by 450 points. Numbers only: no list names, no moods.
struct YearShareImage: View {
    let replay: YearReplay
    let finished: Bool

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 360
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7 * s) {
                    Circle()
                        .trim(from: 0.07, to: 0.93)
                        .stroke(NonnaTheme.ink, style: StrokeStyle(lineWidth: 2 * s))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 16 * s, height: 16 * s)
                    Text("Pomofocus")
                        .font(.system(size: 12 * s, weight: .semibold))
                }
                Spacer(minLength: 0)
                Text(finished ? "My \(String(replay.year)) in focus" : "My \(String(replay.year)) so far")
                    .font(.system(size: 15 * s, weight: .semibold))
                    .foregroundStyle(NonnaTheme.terracotta)
                Text(replay.totalSeconds.yearHoursString)
                    .font(.system(size: 58 * s, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("of focus")
                    .font(.system(size: 15 * s))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                monthBars(s).padding(.top, 22 * s)
                Grid(alignment: .leading, horizontalSpacing: 18 * s, verticalSpacing: 14 * s) {
                    GridRow {
                        stat("\(replay.blockCount)", "blocks", s)
                        stat("\(replay.daysFocused)", replay.daysFocused == 1 ? "day" : "days", s)
                    }
                    GridRow {
                        stat("\(replay.longestStreak)", replay.longestStreak == 1 ? "day streak" : "days in a row", s)
                        stat(replay.bestMonth.map { $0.month.formatted(.dateTime.month(.abbreviated)) } ?? "None", "best month", s)
                    }
                }
                .padding(.top, 20 * s)
                Spacer(minLength: 0)
                Text("Pomofocus for Mac")
                    .font(.system(size: 10 * s, weight: .medium))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .foregroundStyle(NonnaTheme.ink)
            .padding(28 * s)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background {
                ZStack {
                    NonnaTheme.cream
                    RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.28), NonnaTheme.terracotta.opacity(0)],
                                   center: UnitPoint(x: 0.85, y: 0.12), startRadius: 0, endRadius: 300 * s)
                }
            }
        }
    }

    private func monthBars(_ s: CGFloat) -> some View {
        let most = max(1, replay.months.map(\.seconds).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 5 * s) {
            ForEach(Array(replay.months.enumerated()), id: \.offset) { _, month in
                Capsule()
                    .fill(month.month == replay.bestMonth?.month ? NonnaTheme.terracotta
                          : month.seconds > 0 ? NonnaTheme.terracotta.opacity(0.4) : NonnaTheme.strongLine)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3 * s, 54 * s * CGFloat(month.seconds) / CGFloat(most)))
            }
        }
        .frame(height: 54 * s, alignment: .bottom)
    }

    private func stat(_ value: String, _ label: String, _ s: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1 * s) {
            Text(value)
                .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11 * s))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
