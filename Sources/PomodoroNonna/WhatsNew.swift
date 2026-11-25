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
        ("0.23.0", [
            Item(icon: "sidebar.left", title: "A shorter sidebar", detail: "Four places instead of seven: Focus, Tasks, Progress and Settings. The sidebar hides until you move the pointer to the window's left edge."),
            Item(icon: "chart.bar.xaxis", title: "Progress", detail: "The Dashboard, History, your plan and your mood are now in Progress. Overview shows your week, plan, peak hours and recaps, and See more at the bottom has the full details."),
            Item(icon: "wind", title: "One Reset", detail: "When you're drifting mid-block or after a rough block, Reset suggests one thing: a walk, writing it out, a guided breath or a proper rest, and you can pick another. Choose what plays during it in Settings."),
            Item(icon: "paintpalette", title: "Four themes up front", detail: "Match system, Black Ice, London and Layla are listed first. More themes in Settings has the rest."),
            Item(icon: "checklist", title: "A shorter setup", detail: "First launch asks how you like to work, then starts your first block."),
            Item(icon: "text.alignleft", title: "Plainer words", detail: "Text across the app is shorter and says only what you need."),
            Item(icon: "scroll", title: "Slim scroll bars", detail: "Scroll bars are a thin line with no track, even with a mouse connected."),
        ]),
        ("0.22.15", [
            Item(icon: "wind", title: "Breathe together", detail: "When a study group's leader starts a block with the opening breaths, everyone breathes in step and the block starts for all of you at once."),
            Item(icon: "person.2", title: "Group timers follow reliably", detail: "A friend's timer now follows the group even when your Macs' clocks disagree. The Together window shows the leader's timer and when you last heard from it."),
        ]),
        ("0.22.14", [
            Item(icon: "person.2", title: "Joining a group fixed", detail: "Before, every attempt to join a study group failed. If two of you start a group by mistake, the one nobody joined shows the other group to join instead."),
        ]),
        ("0.22.13", [
            Item(icon: "person.2", title: "Study together", detail: "One of you starts a group from Together on the Focus screen, friends in the same room join, and everyone's timer runs the same blocks and breaks. It uses Bluetooth and Wi-Fi, not the internet, and shares only the timer and your first name."),
            Item(icon: "figure.walk", title: "Help when focus slips", detail: "After a rough block, your break suggests a walk if you felt restless, a brain dump or guided reset if you felt scattered, or a proper rest after two tough blocks in a row. Mid-block, Drifting? offers a one-minute reset, a place to park what's on your mind, or ten more minutes to finish small."),
            Item(icon: "clock", title: "Your peak hours", detail: "The Dashboard shows your best two hours, where you finish the most blocks and rate them highest, and your toughest stretch."),
            Item(icon: "chart.line.downtrend.xyaxis", title: "The plan waits for your rating", detail: "Two Restless or Scattered blocks in a row step your plan back a level, and it won't climb right after a rough one. Click a shorter bar on the ladder to step down yourself."),
            Item(icon: "rectangle.on.rectangle", title: "Look before you switch", detail: "Clicking Short rest or Long rest while a block runs no longer stops it. The timer keeps going until you press Start short break or Start long break."),
        ]),
        ("0.22.12", [
            Item(icon: "light.max", title: "A glow when time's up", detail: "When a block or break ends, and at each overtime reminder, the edges of your screen glow, even over a full-screen app and with the sound off. Try it or turn it off in Settings. Notifications also no longer stop when a block runs into overtime."),
            Item(icon: "menubar.rectangle", title: "Menu bar styles", detail: "In Settings → Menu bar, swap the timer chip for three bars that empty as the block runs, your own picture, or Minimal (the time left or a percentage), in the menu bar's colour or any other. You can also hide Pomofocus from the menu bar there."),
            Item(icon: "book", title: "Study away from the screen", detail: "If your Mac locks or sleeps while you work on paper, the block keeps counting to the bell instead of pausing. If you're away past the bell, Pomofocus asks whether you were still focusing, and Count it adds that time."),
            Item(icon: "sun.max", title: "Today includes the block you're in", detail: "The Today total on the Focus screen now counts the running block, as the menu bar and Cinema already did."),
        ]),
        ("0.22.11", [
            Item(icon: "magnifyingglass", title: "Pomofocus in Spotlight", detail: "Search Spotlight for Pomofocus to start a block, pause, resume, skip a break or end a session. Siri knows them too: say \"Start focus in Pomofocus\"."),
            Item(icon: "menubar.rectangle", title: "A lighter menu bar timer", detail: "The clock in the menu bar panel now uses almost no power, like the big clock on the Focus screen."),
        ]),
        ("0.22.10", [
            Item(icon: "rectangle.stack", title: "Your year in focus", detail: "A few cards on your year: hours, biggest month, where the time went, rhythm, longest streak and how it felt, ending with a shareable image that shows only numbers. Open it from the Dashboard, and in December it's offered to you."),
            Item(icon: "playpause", title: "Buttons on the widget and in Control Center", detail: "Start, pause, resume, skip a break or end a session from the desktop widget, or add the buttons to Control Center or the menu bar. The same actions work in Shortcuts and as links like pomofocus://pause."),
            Item(icon: "chart.bar", title: "Hours by week", detail: "A Dashboard chart of your focus hours for each of the last 12 weeks, with your weekly average and this week against the same point last week. Total focus time now shows how much ran past the bell, and Completed sessions shows how many blocks you ended early."),
            Item(icon: "leaf", title: "Lighter on your Mac", detail: "A running timer uses about a third of the power it did while the window is in view, and almost nothing when it's hidden. The menu bar and widget now tick on the same second."),
            Item(icon: "calendar", title: "Your week", detail: "Each week starts with a look back at your focus, best day and time, top list and mood, plus one suggestion for the week ahead. Open it from the Dashboard."),
            Item(icon: "moon", title: "Do Not Disturb during focus", detail: "Turn on Silence notifications during focus in Settings → Experience and Do Not Disturb comes on with each block, then off for your break."),
            Item(icon: "checklist", title: "A short setup", detail: "First launch asks how you like to work, your daily goal, a theme, a sound and a few extras, all optional. Run it again from Settings → Experience."),
            Item(icon: "clock", title: "The time of day", detail: "A clock at the top of the timer shows the current time. Turn it off in Settings → Experience."),
        ]),
        ("0.22.9", [
            Item(icon: "heart.text.square", title: "Daily mood check-in", detail: "Like State of Mind on iPhone: slide to how today feels, then add a word or two, what's behind it and a note. The Dashboard shows your mood over 30 days and five weeks, and it stays on this Mac."),
        ]),
        ("0.22.8", [
            Item(icon: "building.columns", title: "Skyline in Cinema", detail: "With a dark theme, press Skyline (or S) in Cinema to put Westminster at night along the bottom of the screen."),
            Item(icon: "square.on.square.dashed", title: "Glass", detail: "The Glass slider in Settings → Appearance turns the timer, cards and panels from solid to see-through."),
            Item(icon: "cloud.rain", title: "London", detail: "A theme of Westminster across the Thames on a rainy night, with Big Ben at the real time and the Eye turning at its real speed. Turn on rain or a storm in Settings."),
            Item(icon: "wind", title: "Focus reset", detail: "Short guided sessions over rain, binaural beats, meditation music or the voice alone. The window clears to a breathing flower that follows the voice."),
            Item(icon: "captions.bubble", title: "Captions", detail: "Turn on Focus reset captions in Settings to follow along without sound."),
            Item(icon: "calendar", title: "Up next in Cinema", detail: "Under the clock, Cinema shows your next calendar event, how soon it starts and when."),
            Item(icon: "chevron.down.circle", title: "Settings fold up", detail: "Each section folds to its heading and a summary, like your timer lengths."),
            Item(icon: "calendar.day.timeline.left", title: "Fewer blocks on the timeline", detail: "The running block shows where it ends with lined shading, and extra blocks no longer stack underneath."),
        ]),
        ("0.22.7", [
            Item(icon: "calendar.day.timeline.left", title: "Timeline during focus", detail: "The timeline stays open while you focus and shows your next break and block."),
        ]),
        ("0.22.6", [
            Item(icon: "figure.stairs", title: "Easing back in", detail: "After a few days off, blocks start shorter and add five minutes each time you finish one, until you're back at your level."),
            Item(icon: "arrow.down.right", title: "Shorter after a tough block", detail: "Give up on a block, cut it short or rate it Scattered, and the next one is five minutes shorter. A good block puts it back."),
            Item(icon: "circle.inset.filled", title: "Your rating counts", detail: "Flow blocks count twice toward your next level. Scattered or Restless ones don't count as held."),
            Item(icon: "cup.and.saucer", title: "Breaks that fit the block", detail: "After a block full of pauses, or one you kept going long past the end, the break is five minutes longer."),
        ]),
        ("0.22.5", [
            Item(icon: "arrow.down.app", title: "Updates from protected folders", detail: "If Pomofocus is in a folder it can't change, your Mac asks for its password instead of sending you to the website."),
            Item(icon: "hand.point.up.left", title: "Click away to close", detail: "Your focus score, the dashboard details and the plan's sources close when you click outside them."),
            Item(icon: "tv", title: "Cinema labels", detail: "Cinema's small labels no longer use wide letter spacing."),
        ]),
        ("0.22.4", [
            Item(icon: "tray.and.arrow.down", title: "Turn past work into tasks", detail: "Pomofocus offers to turn what you've been focusing on, and your lists, into tasks. You pick which."),
            Item(icon: "circle.inset.filled", title: "Quick session rating", detail: "When you end a session, pick how it felt, from Scattered to Flow."),
            Item(icon: "rectangle.on.rectangle", title: "The widget is back", detail: "Pomofocus shows up in Edit Widgets again, with your timer in three sizes."),
            Item(icon: "timer", title: "Update mid-pomodoro", detail: "Your timer keeps running through an update, and nothing pops up until the block ends."),
            Item(icon: "snowflake", title: "Black Ice, lighter", detail: "The frost now runs on the graphics chip instead of the processor."),
        ]),
        ("0.22.3", [
            Item(icon: "leaf", title: "Simpler Tasks", detail: "Tasks opens on one task with a Start button, and the rest of today is folded away."),
            Item(icon: "text.cursor", title: "Add a task by name", detail: "Type it and press Return. Length, colour and list are optional."),
            Item(icon: "play.circle", title: "A nudge to begin", detail: "After a few minutes of planning, Pomofocus suggests a task to start with. Not yet puts it away."),
            Item(icon: "slider.horizontal.3", title: "The full board", detail: "Turn off Keep tasks simple in Settings for the full board, stats and planning tools."),
        ]),
        ("0.22.2", [
            Item(icon: "circle.fill", title: "Update banner", detail: "When a new version is out, Settings shows a red dot and a banner with Update now."),
            Item(icon: "textformat", title: "Bespoke greeting", detail: "Bespoke now greets you with only your handwritten note."),
        ]),
        ("0.22.1", [
            Item(icon: "calendar.day.timeline.left", title: "Plan your day", detail: "Drag tasks onto the timeline, or press Plan my day to fit them into your free time."),
            Item(icon: "checklist", title: "Steps inside tasks", detail: "Break a task into steps, and the next one shows on the timer while you work."),
            Item(icon: "moon.stars", title: "Wrap up the day", detail: "See what got done and move the rest to tomorrow."),
            Item(icon: "figure.stairs", title: "Warm-up after time off", detail: "After time off you start with shorter warm-up blocks, and a missed day shrinks the goal to one block."),
            Item(icon: "person.crop.circle", title: "Greeting by name", detail: "Tell Pomofocus your name and it greets you when you open it."),
            Item(icon: "arrow.down.circle", title: "In-app updates", detail: "Pomofocus tells you when a new version is out and installs it."),
            Item(icon: "pencil", title: "Edit a session", detail: "Click any session in History to rename it or move it to another list."),
            Item(icon: "arrow.triangle.branch", title: "Switch lists mid-block", detail: "Change list part-way through and the time is split between the two."),
            Item(icon: "star.leadinghalf.filled", title: "Rate once per session", detail: "By default you rate your focus when you end a session, not after every block. Change it in Settings."),
            Item(icon: "calendar.badge.plus", title: "Faster task adding", detail: "Set a task's date, length and list as you type it."),
            Item(icon: "paintpalette", title: "List colours", detail: "Pick any colour for a list. It's used everywhere, including the dashboard."),
            Item(icon: "arrow.up.arrow.down", title: "Arrange the sidebar", detail: "Drag the icons into the order you like. Settings now lives at the bottom."),
            Item(icon: "questionmark.circle", title: "What the numbers mean", detail: "Click the ? next to any dashboard number for an explanation."),
            Item(icon: "waveform", title: "Recorded sounds", detail: "Recordings of a wall clock, rain on a window and ocean waves, plus softer brown and white noise, all looping seamlessly."),
            Item(icon: "camera.macro", title: "Breathing flower", detail: "The breaths before a block show a flower that opens and closes in your theme's colours."),
            Item(icon: "text.cursor", title: "Your intention carries over", detail: "What you're working on stays for the next block until you change it."),
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
                Text(name.isEmpty ? "What's new" : "What's new, \(name)")
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
                Button("Done", action: onDone)
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
