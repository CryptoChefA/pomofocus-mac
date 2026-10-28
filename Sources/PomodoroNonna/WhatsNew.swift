import SwiftUI

/// What changed in each version, shown once after an update and any time from Settings.
/// Written for people, not developers: what you can do now, in a line or two.
enum WhatsNew {
    struct Item: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let lastSeenKey = "lastSeenVersion"

    /// Newest first. Add an entry with every release.
    static let releases: [(version: String, items: [Item])] = [
        ("0.22.1", [
            Item(icon: "calendar.day.timeline.left", title: "Plan your day", detail: "Drag tasks onto the timeline, or press Plan my day to fit them into your free time."),
            Item(icon: "checklist", title: "Steps inside tasks", detail: "Break a task into small steps. The next one shows on the timer while you work."),
            Item(icon: "moon.stars", title: "Wrap up the day", detail: "See what got done and move the rest to tomorrow in one click."),
            Item(icon: "figure.stairs", title: "A plan that adapts", detail: "After time off you start with shorter warm-up blocks, and a missed day shrinks the goal to one block."),
            Item(icon: "person.crop.circle", title: "A personal welcome", detail: "Tell Pomofocus your name and it greets you when you open it."),
            Item(icon: "arrow.down.circle", title: "One-click updates", detail: "Pomofocus now tells you when a new version is out and installs it for you."),
            Item(icon: "pencil", title: "Fix a session", detail: "Click any session in History to rename it or move it to another list."),
            Item(icon: "arrow.triangle.branch", title: "Switch lists mid-block", detail: "Change list part-way through and the time is split between the two."),
            Item(icon: "star.leadinghalf.filled", title: "Rate once per session", detail: "By default you rate your focus when you end a session, not after every block. Change it in Settings."),
            Item(icon: "calendar.badge.plus", title: "Faster task adding", detail: "Start typing a task to pick its date, length and list right there."),
            Item(icon: "paintpalette", title: "Your colours", detail: "Pick any colour for a list. It's used everywhere, including the dashboard."),
            Item(icon: "arrow.up.arrow.down", title: "Arrange the sidebar", detail: "Drag the icons into the order you like. Settings now lives at the bottom."),
            Item(icon: "questionmark.circle", title: "What the numbers mean", detail: "Click the small ? next to any dashboard number for a plain explanation."),
            Item(icon: "waveform", title: "Real sounds", detail: "A real wall clock, rain on a window and ocean waves, plus softer brown and white noise that loop without a seam."),
            Item(icon: "sparkles", title: "A new breathing flower", detail: "The breaths before a block bloom and fold in your theme's colours."),
            Item(icon: "text.cursor", title: "Your intention carries on", detail: "What you're working on stays for the next block until you change it."),
        ]),
    ]

    @MainActor static var current: [Item] {
        let version = Updater.shared.currentVersion
        return releases.first { $0.version == version }?.items ?? releases.first?.items ?? []
    }
}

struct WhatsNewSheet: View {
    @AppStorage("displayName") private var displayName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let onDone: () -> Void

    private var name: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What's new in \(Updater.shared.currentVersion)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(NonnaTheme.terracotta)
                Text(name.isEmpty ? "Fresh from the workshop." : "Fresh for you, \(name).")
                    .font(.system(size: 32, weight: .regular, design: .serif))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(WhatsNew.current.enumerated()), id: \.element.id) { index, item in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: item.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(NonnaTheme.terracotta)
                                .frame(width: 30, height: 30)
                                .background(NonnaTheme.terracotta.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 13, weight: .semibold))
                                Text(item.detail)
                                    .font(.system(size: 12))
                                    .foregroundStyle(NonnaTheme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared || reduceMotion ? 0 : 8)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.05 * Double(index)), value: appeared)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)

            if name.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .foregroundStyle(NonnaTheme.terracotta)
                    TextField("What should we call you? (optional)", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Lovely", action: onDone)
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 520)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .onAppear { appeared = true }
    }
}

/// "Welcome back, Sam": the app opens on a calm card in the theme's colour. The greeting
/// sharpens out of a soft blur and settles, a fine accent line draws beneath it, and then
/// the whole card dissolves to reveal the app. It never blocks a click.
struct LaunchGreeting: View {
    @AppStorage("displayName") private var displayName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 hidden, 1 greeting in, 2 dissolving away.
    @State private var stage = 0
    @State private var veil = true
    /// Once per launch, however many windows open.
    @MainActor private static var shown = false

    var body: some View {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ZStack {
            if veil, !name.isEmpty {
                NonnaTheme.cream
                    .overlay {
                        RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.10), .clear], center: .center, startRadius: 10, endRadius: 520)
                    }
                    .opacity(stage == 2 ? 0 : 1)
                VStack(spacing: 14) {
                    Text(Self.salutation)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .opacity(stage == 1 ? 1 : 0)
                        .offset(y: stage == 0 ? 6 : 0)
                    Text("Welcome back, \(name).")
                        .font(.system(size: 48, weight: .regular, design: .serif))
                        .tracking(-0.8)
                        .foregroundStyle(NonnaTheme.ink)
                        .opacity(stage == 1 ? 1 : 0)
                        .blur(radius: stage == 1 ? 0 : 10)
                        .scaleEffect(stage == 0 ? 0.985 : (stage == 2 ? 1.015 : 1))
                    Capsule()
                        .fill(NonnaTheme.terracotta)
                        .frame(width: stage == 1 ? 120 : 0, height: 1.5)
                        .opacity(stage == 1 ? 0.9 : 0)
                }
                .compositingGroup()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task {
            guard !Self.shown, !displayName.isEmpty else { veil = false; return }
            Self.shown = true
            if reduceMotion {
                stage = 1
                try? await Task.sleep(for: .seconds(1.6))
                stage = 2
                veil = false
                return
            }
            // Let the window finish its first layout so nothing competes with the motion.
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 1.1)) { stage = 1 }
            try? await Task.sleep(for: .seconds(2.1))
            withAnimation(.timingCurve(0.65, 0, 0.35, 1, duration: 0.9)) { stage = 2 }
            try? await Task.sleep(for: .seconds(0.95))
            veil = false
        }
    }

    private static var salutation: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
    }
}
