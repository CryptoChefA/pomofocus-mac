import AppKit
import Charts
import SwiftUI

enum MoodPrompt {
    /// Settings → Experience: ask once a day.
    static let enabledKey = "mood.dailyPrompt"
    /// The day "Not today" was pressed, as a start-of-day time interval.
    static let skippedKey = "mood.skippedDay"
}

/// The mood scale's own colours, the same in every theme so a colour always means the same
/// thing: indigo for very unpleasant, through blue, teal and green, to gold and orange for
/// very pleasant. A little deeper on light themes so they hold their contrast.
enum MoodColor {
    private static let stops = ["7166D4", "5E83DA", "4FA6C9", "5FB79F", "9CC66B", "E6B84F", "F28C4A"]

    /// `level` runs 1 to 7; fractions fall between the stops.
    static func rgb(_ level: Double) -> RGB {
        let x = min(6, max(0, level - 1))
        let index = Int(x.rounded(.down))
        var color = RGB(hex: stops[index])
        if index < 6 { color = color.mixed(with: RGB(hex: stops[index + 1]), x - Double(index)) }
        if !NonnaTheme.isDark { color = color.mixed(with: RGB(r: 0, g: 0, b: 0), 0.12) }
        return color
    }

    static func color(_ level: Double) -> Color { Color(hex: rgb(level).hex) }
    static func color(valence: Double) -> Color { color(1 + 6 * valence) }
    static func glow(valence: Double) -> Color { Color(hex: rgb(1 + 6 * valence).mixed(with: RGB(r: 1, g: 1, b: 1), 0.45).hex) }
    static var spectrum: [Color] { (1...7).map { color(Double($0)) } }

    static func tone(_ average: Double) -> String {
        average >= 4.5 ? "Mostly pleasant" : average <= 3.5 ? "Mostly unpleasant" : "Mixed"
    }
}

// MARK: - The shape

/// One shape for the whole scale: a soft eight-petalled flower when things are very good,
/// whose petals narrow and sharpen as the mood drops, until they're the points of a tight,
/// spiky star when things are very hard. It morphs smoothly all the way along.
struct MoodShape: Shape {
    var valence: Double

    var animatableData: Double {
        get { valence }
        set { valence = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let v = min(1, max(0, valence)), hard = 1 - v
        // How pointed each lobe is: round petals (a low power) through to needle-sharp spikes.
        let sharpness = 0.55 * pow(12 / 0.55, hard)
        // How far the lobes reach out from the centre: deepest for the spikes.
        let depth = 0.3 + 0.24 * pow(hard, 1.4)
        let lobes = 8.0
        var path = Path()
        let steps = 480
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi - .pi / 2
            let lobe = pow(abs(cos(angle * lobes / 2)), sharpness)
            let r = (1 + depth * lobe) / (1 + depth)
            let point = CGPoint(x: center.x + cos(angle) * radius * r, y: center.y + sin(angle) * radius * r)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Three translucent layers of the shape, turning slowly against each other, glowing in the
/// mood's colour. Hard moods sit a little smaller; good ones open up.
struct MoodBloom: View {
    let valence: Double
    var turning = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var turned = false

    var body: some View {
        let color = MoodColor.color(valence: valence), glow = MoodColor.glow(valence: valence)
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(0..<3, id: \.self) { layer in
                    MoodShape(valence: valence)
                        .fill(RadialGradient(colors: [glow.opacity(0.95), color.opacity(0.75), color.opacity(0.3)],
                                             center: .center, startRadius: 0, endRadius: size * 0.5))
                        .scaleEffect(1 - Double(layer) * 0.17)
                        .rotationEffect(.degrees(Double(layer) * 13 + (turned ? (layer.isMultiple(of: 2) ? 360 : -360) : 0)))
                        .opacity(layer == 0 ? 0.7 : 0.55)
                        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
                }
            }
            .compositingGroup()
            .scaleEffect(0.82 + 0.18 * valence)
            .shadow(color: color.opacity(0.45), radius: size * 0.12)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
        .onAppear {
            guard turning, !reduceMotion else { return }
            withAnimation(.linear(duration: 90).repeatForever(autoreverses: false)) { turned = true }
        }
    }
}

// MARK: - Button

/// Always at the top of the Focus screen, so a check-in is one click away even after the
/// banner is dismissed. Before you've checked in it's a faint, still flower; afterwards it
/// shows today's shape and colour, and clicking it lets you change your answer.
struct MoodButton: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let today = model.todaysCheckIn
        Button { model.showsMoodCheckIn = true } label: {
            MoodBloom(valence: today.map { MoodScale.valence(forLevel: $0.level) } ?? 0.62, turning: false)
                .frame(width: 22, height: 22)
                .opacity(today == nil ? (hovering ? 0.85 : 0.45) : 1)
                .saturation(today == nil ? 0.2 : 1)
                .frame(width: 40, height: 40)
                .background(NonnaTheme.pane(NonnaTheme.raisedPaper, hovering ? 1 : 0.7), in: Circle())
                .overlay { Circle().stroke(NonnaTheme.line, lineWidth: 0.8) }
                .scaleEffect(hovering ? 1.05 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .help(today.map { "Today: \(MoodScale.title($0.level)). Click to change it" } ?? "How are you feeling today?")
        .accessibilityLabel("How are you feeling today?")
        .accessibilityValue(today.map { MoodScale.title($0.level) } ?? "Not checked in")
    }
}

// MARK: - Banner

/// "How are you feeling today?" on the Focus screen, once a day, never during a block.
struct MoodCheckInBanner: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MoodPrompt.enabledKey) private var enabled = true
    @AppStorage(MoodPrompt.skippedKey) private var skippedDay = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var skippedToday: Bool {
        Calendar.current.isDateInToday(Date(timeIntervalSinceReferenceDate: skippedDay))
    }

    var body: some View {
        if enabled, model.status == .idle, model.todaysCheckIn == nil, !skippedToday {
            HStack(spacing: 12) {
                MoodBloom(valence: 0.62, turning: false)
                    .frame(width: 22, height: 22)
                Text("How are you feeling today?")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Check in") { model.showsMoodCheckIn = true }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                Button {
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) {
                        skippedDay = Calendar.current.startOfDay(for: Date()).timeIntervalSinceReferenceDate
                    }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.secondaryInk)
                .help("Not today. You can check in any time with the flower at the top")
                .accessibilityLabel("Not today")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NonnaTheme.pane(NonnaTheme.raisedPaper, 0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
            .transition(.banner(reduceMotion: reduceMotion))
        }
    }
}

// MARK: - Check-in

/// Slide to how today feels, then, if you like, a word or two for it, what's behind it and a
/// line of your own. Only the first step is needed.
struct MoodCheckInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onClose: () -> Void

    @State private var step = 0
    @State private var valence = 0.5
    @State private var feelings: [String] = []
    @State private var influences: [String] = []
    @State private var note = ""
    @State private var showsAllFeelings = false
    @State private var existing: MoodCheckIn?
    @State private var logged = false

    private var level: Int { MoodScale.level(forValence: valence) }
    private var color: Color { MoodColor.color(valence: valence) }

    var body: some View {
        ZStack {
            // The whole sheet takes on the mood's colour.
            NonnaTheme.cream
            RadialGradient(colors: [color.opacity(NonnaTheme.isDark ? 0.32 : 0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 10, endRadius: 420)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: level)

            if logged {
                loggedView.transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .help("Close without saving")
                        .accessibilityLabel("Close")
                        .keyboardShortcut(.cancelAction)
                    }

                    ZStack {
                        switch step {
                        case 0: levelStep.transition(stepTransition)
                        case 1: feelingsStep.transition(stepTransition)
                        default: influencesStep.transition(stepTransition)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    footer
                }
                .padding(26)
                .transition(.opacity)
            }
        }
        .frame(width: 560, height: 640)
        .onAppear(perform: prefill)
        .onChange(of: level) { _, _ in
            // A soft tick on the trackpad as you pass each step, like a detent.
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { go(to: step - 1) }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            Spacer()
            if step < 2 {
                Button("Next") { go(to: step + 1) }
                    .buttonStyle(NonnaButtonStyle(color: color))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Done", action: save)
                    .buttonStyle(NonnaButtonStyle(color: color))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var stepTransition: AnyTransition {
        // The outgoing step clears quickly, so the two never read on top of each other.
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)).animation(.easeOut(duration: 0.3).delay(0.08)),
                                              removal: .opacity.animation(.easeIn(duration: 0.1)))
    }

    private func prefill() {
        guard existing == nil, let today = model.todaysCheckIn else { return }
        existing = today
        valence = MoodScale.valence(forLevel: today.level)
        feelings = today.feelings
        influences = today.influences
        note = today.note ?? ""
    }

    private func go(to next: Int) {
        // Words from the far side of the scale drop off when the slider has moved a long way.
        feelings = feelings.filter { abs((MoodScale.valence(ofFeeling: $0) ?? valence) - valence) <= 0.4 }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.05)) { step = next }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        model.saveCheckIn(MoodCheckIn(id: existing?.id ?? UUID(), date: Date(), level: level,
                                      feelings: feelings, influences: influences,
                                      valence: valence, note: trimmed.isEmpty ? nil : String(trimmed.prefix(280))))
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { logged = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.9 : 1.6))
            onClose()
        }
    }

    // Step 1

    private var levelStep: some View {
        VStack(spacing: 20) {
            Text("How are you feeling today?")
                .font(.system(size: 24, weight: .semibold))
            Text("Choose how you've felt overall today.")
                .font(.system(size: 13))
                .foregroundStyle(NonnaTheme.secondaryInk)
            MoodBloom(valence: valence)
                .frame(width: 230, height: 230)
                .animation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.12), value: valence)
                .padding(.vertical, 6)
            Text(MoodScale.title(level))
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : NonnaMotion.quick, value: level)
            VStack(spacing: 8) {
                MoodSlider(valence: $valence)
                HStack {
                    Text("Very unpleasant")
                    Spacer()
                    Text("Very pleasant")
                }
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
            }
            .frame(maxWidth: 400)
        }
    }

    // Step 2

    private var feelingsStep: some View {
        let nearby = MoodScale.feelings(near: valence)
        let words = showsAllFeelings
            ? MoodScale.vocabulary.map(\.word)
            : nearby + feelings.filter { !nearby.contains($0) }
        return VStack(spacing: 16) {
            stepHeader
            Text("What best describes this feeling?")
                .font(.system(size: 22, weight: .semibold))
            Text("Pick any that fit, or none.")
                .font(.system(size: 13))
                .foregroundStyle(NonnaTheme.secondaryInk)
            ScrollView {
                FlowLayout(spacing: 8, centered: true) {
                    ForEach(words, id: \.self) { word in
                        MoodChip(title: word, selected: feelings.contains(word),
                                 tint: MoodColor.color(valence: MoodScale.valence(ofFeeling: word) ?? valence)) {
                            toggle(word, in: &feelings)
                        }
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: showsAllFeelings ? 250 : 150)
            Button(showsAllFeelings ? "Show fewer" : "Show all") {
                withAnimation(reduceMotion ? nil : NonnaMotion.quick) { showsAllFeelings.toggle() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    // Step 3

    private var influencesStep: some View {
        VStack(spacing: 16) {
            stepHeader
            Text("What's having the biggest impact on you?")
                .font(.system(size: 22, weight: .semibold))
                .multilineTextAlignment(.center)
            FlowLayout(spacing: 8, centered: true) {
                ForEach(MoodScale.influences, id: \.name) { item in
                    MoodChip(title: item.name, icon: item.icon, selected: influences.contains(item.name), tint: color) {
                        toggle(item.name, in: &influences)
                    }
                }
            }
            .frame(maxWidth: 480)
            TextField("Anything else? A line in your own words, if you like", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(2...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NonnaTheme.pane(NonnaTheme.raisedPaper, 0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
                .frame(maxWidth: 440)
                .padding(.top, 6)
        }
    }

    private var stepHeader: some View {
        HStack(spacing: 10) {
            MoodBloom(valence: valence, turning: false).frame(width: 40, height: 40)
            Text(MoodScale.title(level))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var loggedView: some View {
        VStack(spacing: 18) {
            MoodBloom(valence: valence)
                .frame(width: 170, height: 170)
            Text("Thanks for checking in")
                .font(.system(size: 22, weight: .semibold))
            Text(MoodScale.isUnpleasant(level) ? "Go gently with yourself today."
                 : MoodScale.isPleasant(level) ? "Enjoy it. Days like this are worth noticing." : "Noticing is the first step.")
                .font(.system(size: 13))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    private func toggle(_ name: String, in list: inout [String]) {
        if let index = list.firstIndex(of: name) { list.remove(at: index) } else { list.append(name) }
    }
}

/// A wide slider on the mood scale's colours. The knob locks onto the seven dots as you drag,
/// springing from one to the next with a tick on the trackpad. Arrow keys move one step;
/// VoiceOver can adjust it too.
private struct MoodSlider: View {
    @Binding var valence: Double
    @FocusState private var focused: Bool
    private let knob: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let travel = max(1, proxy.size.width - knob)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: MoodColor.spectrum, startPoint: .leading, endPoint: .trailing))
                    .opacity(0.7)
                    .frame(height: 10)
                    .padding(.horizontal, knob / 2 - 5)
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 3, height: 3)
                        .offset(x: knob / 2 + travel * CGFloat(index) / 6 - 1.5)
                }
                Circle()
                    .fill(MoodColor.color(valence: valence))
                    .overlay { Circle().stroke(Color.white.opacity(0.92), lineWidth: 3) }
                    .overlay { Circle().stroke(focused ? NonnaTheme.ink.opacity(0.6) : .clear, lineWidth: 1).padding(-4) }
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .offset(x: travel * valence)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let raw = min(1, max(0, (drag.location.x - knob / 2) / travel))
                let snapped = MoodScale.valence(forLevel: MoodScale.level(forValence: raw))
                focused = true
                guard snapped != valence else { return }
                withAnimation(.spring(duration: 0.28, bounce: 0.18)) { valence = snapped }
            })
        }
        .frame(height: 34)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.leftArrow) { nudge(-1); return .handled }
        .onKeyPress(.rightArrow) { nudge(1); return .handled }
        .accessibilityElement()
        .accessibilityLabel("How you're feeling")
        .accessibilityValue(MoodScale.title(MoodScale.level(forValence: valence)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: nudge(1)
            case .decrement: nudge(-1)
            @unknown default: break
            }
        }
    }

    /// One step along the scale, landing on the nearest step.
    private func nudge(_ steps: Int) {
        let level = MoodScale.level(forValence: valence) + steps
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { valence = MoodScale.valence(forLevel: level) }
    }
}

private struct MoodChip: View {
    let title: String
    var icon: String?
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NonnaTheme.ink)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(selected ? tint.opacity(0.28) : NonnaTheme.pane(NonnaTheme.raisedPaper, 0.9), in: Capsule())
            .overlay { Capsule().stroke(selected ? tint : NonnaTheme.line, lineWidth: selected ? 1.2 : 0.8) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Dashboard

/// Today, the last 30 days as a line and as a calendar, the words that come up most, what's
/// been affecting you, and how focus tends to go on good days and hard ones.
struct MoodCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
    @State private var selectedDay: Date?

    var body: some View {
        let summary = MoodSummary.calculate(checkIns: model.moodCheckIns, focusByDay: model.focusSecondsByDay)
        NonnaCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 7) {
                    Text("Mood")
                        .font(.system(size: 18, weight: .semibold))
                    InfoButton(title: "Mood", text: "Your daily check-ins. The line shows the last 30 days, higher is more pleasant; hover a day to see what you picked. The calendar shows the last five weeks. Check-ins stay on this Mac, like everything else in Pomofocus.")
                    Spacer()
                    Button(model.todaysCheckIn == nil ? "Check in" : "Update today") { model.showsMoodCheckIn = true }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                }

                if summary.checkInsInWindow == 0 {
                    VStack(spacing: 12) {
                        MoodBloom(valence: 0.62).frame(width: 70, height: 70)
                        Text("No check-ins yet")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Check in once a day to see how your mood moves over the weeks, and what shapes it.")
                            .font(.system(size: 13))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } else {
                    todayLine(summary)
                    let charts = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                                         : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                    charts {
                        chart(summary)
                        MoodCalendar(checkIns: model.moodCheckIns)
                    }
                    let lists = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                                        : AnyLayout(HStackLayout(alignment: .top, spacing: 32))
                    lists {
                        feelingsList(summary)
                        influencesList(summary)
                    }
                    if let good = summary.focusOnGoodDays, let hard = summary.focusOnHardDays {
                        Text(focusLine(good: good, hard: hard))
                            .font(.system(size: 12))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if summary.heavyStretch {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "heart")
                                .foregroundStyle(MoodColor.color(2))
                            Text("It's been a heavy couple of weeks. Talking with someone you trust, or your school's counselling service, can really help. If it ever feels like too much, reach out to a crisis line where you live.")
                                .font(.system(size: 12))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .background(NonnaTheme.pane(NonnaTheme.raisedPaper, 0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    private func todayLine(_ summary: MoodSummary) -> some View {
        HStack(spacing: 14) {
            if let today = model.todaysCheckIn {
                MoodBloom(valence: today.valence ?? MoodScale.valence(forLevel: today.level))
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today: \(MoodScale.title(today.level))")
                        .font(.system(size: 15, weight: .semibold))
                    Text(([today.feelings.joined(separator: ", ")].filter { !$0.isEmpty } + [today.note ?? ""].filter { !$0.isEmpty }).joined(separator: ". ").ifEmpty("\(summary.checkInsInWindow) check-ins in the last 30 days"))
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .lineLimit(2)
                }
            } else {
                MoodBloom(valence: 0.5, turning: false)
                    .frame(width: 46, height: 46)
                    .opacity(0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not checked in today")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(summary.checkInsInWindow) check-ins in the last 30 days")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
    }

    private func chart(_ summary: MoodSummary) -> some View {
        let calendar = Calendar.current
        let byDay = Dictionary(model.moodCheckIns.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, latest in latest })
        let points = summary.days.compactMap { day in byDay[day.day].map { (day: day.day, checkIn: $0) } }
        let first = summary.days.first?.day ?? Date()
        let end = calendar.date(byAdding: .day, value: 1, to: summary.days.last?.day ?? Date()) ?? Date()
        let selected = selectedDay.flatMap { day in byDay[calendar.startOfDay(for: day)] }
        func value(_ checkIn: MoodCheckIn) -> Double { 1 + 6 * (checkIn.valence ?? MoodScale.valence(forLevel: checkIn.level)) }
        return Chart {
            ForEach(points, id: \.day) { point in
                LineMark(x: .value("Day", point.day, unit: .day), y: .value("Mood", value(point.checkIn)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(NonnaTheme.strongLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(points, id: \.day) { point in
                PointMark(x: .value("Day", point.day, unit: .day), y: .value("Mood", value(point.checkIn)))
                    .foregroundStyle(MoodColor.color(value(point.checkIn)))
                    .symbolSize(selected?.id == point.checkIn.id ? 170 : 80)
                    .accessibilityLabel(point.day.formatted(.dateTime.weekday(.wide).month().day()))
                    .accessibilityValue(([MoodScale.title(point.checkIn.level)] + point.checkIn.feelings).joined(separator: ", "))
            }
            if let selected {
                RuleMark(x: .value("Day", calendar.startOfDay(for: selected.date), unit: .day))
                    .foregroundStyle(NonnaTheme.line)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        MoodTooltip(checkIn: selected)
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartXScale(domain: first...end)
        .chartYScale(domain: 0.5...7.5)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1, 4, 7]) { value in
                AxisGridLine().foregroundStyle(NonnaTheme.line)
                AxisValueLabel {
                    let level = value.as(Int.self) ?? 4
                    Text(level == 1 ? "Unpleasant" : level == 7 ? "Pleasant" : "Neutral")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func feelingsList(_ summary: MoodSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Felt most often")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
            if summary.topFeelings.isEmpty {
                Text("Name a feeling when you check in and it'll show here.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            ForEach(summary.topFeelings) { item in
                HStack(spacing: 9) {
                    Circle()
                        .fill(MoodColor.color(valence: MoodScale.valence(ofFeeling: item.name) ?? (item.averageLevel - 1) / 6))
                        .frame(width: 8, height: 8)
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 12)
                    Text(item.count == 1 ? "1 day" : "\(item.count) days")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func influencesList(_ summary: MoodSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("What's been affecting you")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
            if summary.topInfluences.isEmpty {
                Text("Pick what's having an impact when you check in and it'll show here.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            ForEach(summary.topInfluences) { item in
                HStack(spacing: 9) {
                    Image(systemName: MoodScale.icon(forInfluence: item.name))
                        .font(.system(size: 11))
                        .foregroundStyle(MoodColor.color(item.averageLevel))
                        .frame(width: 16)
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 12)
                    Text(MoodColor.tone(item.averageLevel))
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func focusLine(good: Int, hard: Int) -> String {
        var line = "On days you felt good, you focused \(good.focusDurationString) on average. On harder days, \(hard.focusDurationString)."
        if hard < good { line += " Hard days happen; shorter blocks and a kinder goal can help on those." }
        return line
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// What you picked on a day, shown when hovering the chart or the calendar.
private struct MoodTooltip: View {
    let checkIn: MoodCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(checkIn.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.system(size: 10))
                .foregroundStyle(NonnaTheme.secondaryInk)
            HStack(spacing: 6) {
                Circle().fill(MoodColor.color(valence: checkIn.valence ?? MoodScale.valence(forLevel: checkIn.level)))
                    .frame(width: 8, height: 8)
                Text(MoodScale.title(checkIn.level)).font(.system(size: 12, weight: .semibold))
            }
            if !checkIn.feelings.isEmpty {
                Text(checkIn.feelings.joined(separator: ", ")).font(.system(size: 11))
            }
            if !checkIn.influences.isEmpty {
                Text(checkIn.influences.joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            if let note = checkIn.note {
                Text(note)
                    .font(.system(size: 11, design: .serif))
                    .italic()
                    .lineLimit(3)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
        .padding(10)
        .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
        .shadow(color: NonnaTheme.shadow, radius: 8, y: 3)
    }
}

/// The last five weeks, one dot a day in the mood's colour; an empty ring where there was no
/// check-in. Nothing is counted or kept up: a missed day is just a gap.
private struct MoodCalendar: View {
    let checkIns: [MoodCheckIn]
    @State private var hovered: Date?

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let byDay = Dictionary(checkIns.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { _, latest in latest })
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let start = calendar.date(byAdding: .day, value: -28, to: weekStart) ?? today
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }

        VStack(alignment: .leading, spacing: 8) {
            Text("Last five weeks")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NonnaTheme.secondaryInk)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdays[index])
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .frame(width: 20)
                    }
                }
                ForEach(0..<5, id: \.self) { week in
                    GridRow {
                        ForEach(0..<7, id: \.self) { weekday in
                            let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? today
                            dot(for: day, checkIn: byDay[day], today: today)
                        }
                    }
                }
            }
            if let hovered, let checkIn = byDay[hovered] {
                Text("\(hovered.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(MoodScale.title(checkIn.level))")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            } else {
                Text(" ").font(.system(size: 11))
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func dot(for day: Date, checkIn: MoodCheckIn?, today: Date) -> some View {
        Group {
            if day > today {
                Color.clear
            } else if let checkIn {
                Circle()
                    .fill(MoodColor.color(valence: checkIn.valence ?? MoodScale.valence(forLevel: checkIn.level)))
                    .overlay { Circle().stroke(NonnaTheme.ink.opacity(day == today ? 0.8 : 0), lineWidth: 1.5).padding(-3) }
                    .onHover { hovered = $0 ? day : (hovered == day ? nil : hovered) }
                    .help("\(day.formatted(.dateTime.month(.abbreviated).day())): \(MoodScale.title(checkIn.level))")
            } else {
                Circle()
                    .stroke(day == today ? NonnaTheme.ink.opacity(0.6) : NonnaTheme.line, lineWidth: day == today ? 1.5 : 1)
                    .padding(2)
            }
        }
        .frame(width: 20, height: 20)
        .accessibilityElement()
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(checkIn.map { MoodScale.title($0.level) } ?? "No check-in")
    }
}
