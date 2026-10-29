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
        ("0.22.7", [
            Item(icon: "calendar.day.timeline.left", title: "Your day stays in view", detail: "The timeline stays open while you focus, and shows your break and next block ahead, so you can see where the time is going."),
        ]),
        ("0.22.6", [
            Item(icon: "figure.stairs", title: "Easing back in", detail: "After a few days off, blocks start shorter and add five minutes each time you finish one, until you're back at your level."),
            Item(icon: "arrow.down.right", title: "A tough block, a shorter next one", detail: "Give up on a block, cut it short or rate it Scattered, and the next one is five minutes shorter. A good block puts it back."),
            Item(icon: "circle.inset.filled", title: "Your rating counts", detail: "Flow blocks count twice toward your next level. Scattered or Restless ones don't count as held."),
            Item(icon: "cup.and.saucer", title: "Breaks that fit the block", detail: "After a block full of pauses, or one you kept going long past the end, the break is five minutes longer."),
        ]),
        ("0.22.5", [
            Item(icon: "arrow.down.app", title: "Updates that just work", detail: "If Pomofocus is in a folder it can't change, your Mac asks for its password instead of sending you to the website."),
            Item(icon: "hand.point.up.left", title: "Click away to close", detail: "Your focus score, the dashboard details and the plan's sources close when you click outside them."),
            Item(icon: "tv", title: "Calmer Cinema", detail: "Cinema mode's small labels read plainly now, without the wide letter spacing."),
        ]),
        ("0.22.4", [
            Item(icon: "tray.and.arrow.down", title: "Your work, now in Tasks", detail: "Pomofocus offers to turn what you've been focusing on, and your lists, into tasks. You pick which."),
            Item(icon: "circle.inset.filled", title: "Rate a session in one click", detail: "When you end a session, just pick how it felt, from Scattered to Flow. No writing."),
            Item(icon: "rectangle.on.rectangle", title: "The widget is back", detail: "Pomofocus shows up in Edit Widgets again, with your timer in three sizes."),
            Item(icon: "timer", title: "Update mid-pomodoro", detail: "Your timer keeps running through an update, and nothing pops up until the block ends."),
            Item(icon: "snowflake", title: "Black Ice, lighter", detail: "The frost grows and thaws on the graphics side now, so the theme leaves the processor alone while it moves."),
        ]),
        ("0.22.3", [
            Item(icon: "leaf", title: "Tasks, kept simple", detail: "Tasks opens on one thing to do now, with a Start button. The rest of today folds away until you want it."),
            Item(icon: "text.cursor", title: "Add a task, then get going", detail: "Type it and press Return. No length, colour or list to choose unless you want to."),
            Item(icon: "play.circle", title: "A nudge to begin", detail: "After a few minutes of planning, Pomofocus suggests a task to start with. Not yet puts it away."),
            Item(icon: "slider.horizontal.3", title: "Everything's still there", detail: "Turn off Keep tasks simple in Settings for the full board, stats and planning tools."),
        ]),
        ("0.22.2", [
            Item(icon: "circle.fill", title: "Updates you won't miss", detail: "When a new version is out, a red dot appears on Settings and a banner there lets you update with one click."),
            Item(icon: "textformat", title: "A cleaner Bespoke", detail: "Bespoke now greets you with just your handwritten note."),
        ]),
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
            Item(icon: "camera.macro", title: "A new breathing flower", detail: "The breaths before a block bloom and fold in your theme's colours."),
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
    /// Decided once when the sheet opens, so the field stays put while the name is typed.
    @State private var asksForName = (UserDefaults.standard.string(forKey: "displayName") ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

            if asksForName {
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
