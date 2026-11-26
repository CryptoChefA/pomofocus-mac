import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(MoodPrompt.enabledKey) private var dailyCheckIn = true
    @AppStorage(QuietClock.enabledKey) private var showsClock = true
    @EnvironmentObject private var calendarStore: CalendarStore
    @Environment(\.compactLayout) private var compact

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(
                    title: "Settings",
                    subtitle: "Pomofocus \(Updater.shared.currentVersion). No account, no tracking."
                )

                UpdateBanner()

                NameSettingsRow()

                AppearanceSettingsCard()

                AdaptiveColumns(compact) {
                    VStack(spacing: 18) {
                        timerSettings
                        rhythmSettings
                    }
                    VStack(spacing: 18) {
                        experienceSettings
                        ShortcutSettingsCard()
                        MenuBarSettingsCard()
                        widgetSettings
                        calendarSettings
                        privacySettings
                        UpdateSettingsCard()
                        ShareSettingsCard()
                    }
                }
            }
            .padding(30)
        }
    }

    private var timerSettings: some View {
        SettingsCard(title: "Timer", icon: "timer",
                     summary: "\(model.settings.focusMinutes) min focus, \(model.settings.shortBreakMinutes) min break") {
            StepperRow(
                title: "Focus duration",
                value: "\(model.settings.focusMinutes) min",
                range: 5...180,
                step: 5,
                binding: settingsBinding(\.focusMinutes)
            )
            StepperRow(
                title: "Short break",
                value: "\(model.settings.shortBreakMinutes) min",
                range: 1...30,
                step: 1,
                binding: settingsBinding(\.shortBreakMinutes)
            )
            StepperRow(
                title: "Long break",
                value: "\(model.settings.longBreakMinutes) min",
                range: 5...60,
                step: 5,
                binding: settingsBinding(\.longBreakMinutes)
            )
            StepperRow(
                title: "Long break every",
                value: "\(model.settings.longBreakEvery) sessions",
                range: 2...8,
                step: 1,
                binding: settingsBinding(\.longBreakEvery)
            )
        }
    }

    private var rhythmSettings: some View {
        SettingsCard(title: "Rhythm", icon: "chart.line.uptrend.xyaxis",
                     summary: "\((model.settings.dailyGoalMinutes * 60).focusDurationString) a day") {
            StepperRow(
                title: "Daily focus goal",
                value: (model.settings.dailyGoalMinutes * 60).focusDurationString,
                range: 15...720,
                step: 15,
                binding: settingsBinding(\.dailyGoalMinutes)
            )
            ToggleRow(
                title: "Allow overtime",
                subtitle: "Keep counting when focus time ends",
                binding: settingsBinding(\.allowOvertime)
            )
            ToggleRow(
                title: "Start breaks automatically",
                subtitle: "As soon as a focus block ends",
                binding: settingsBinding(\.autoStartBreaks)
            )
            ToggleRow(
                title: "Start focus automatically",
                subtitle: "As soon as a break ends",
                binding: settingsBinding(\.autoStartFocus)
            )
        }
    }

    private var experienceSettings: some View {
        SettingsCard(title: "Experience", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 12) {
                    Image(systemName: model.settings.ambientSound.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NonnaTheme.gold)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Focus ambience")
                            .font(.system(size: 12, weight: .medium, design: .default))
                        Text(model.settings.ambientSound.subtitle)
                            .font(.system(size: 10, design: .default))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    Spacer()
                    Picker("Focus ambience", selection: settingsBinding(\.ambientSound)) {
                        ForEach(AmbientSound.allCases) { sound in
                            Label(sound.title, systemImage: sound.icon).tag(sound)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                if model.settings.ambientSound != .off {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.wave.1.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                        Slider(value: settingsBinding(\.ambientVolume), in: 0.05...1)
                            .tint(NonnaTheme.terracotta)
                        Button {
                            model.previewAmbientSound()
                        } label: {
                            Label("Preview", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .semibold, design: .default))
                        .foregroundStyle(NonnaTheme.terracotta)
                    }
                    .padding(.leading, 34)
                }
            }
            ToggleRow(
                title: "Opening breath ritual",
                subtitle: "3 rounds, 4 sec in, 6 sec out",
                binding: settingsBinding(\.breathingEnabled)
            )
            StepperRow(
                title: "Presence chime",
                value: model.settings.presenceChimeMinutes == 0 ? "Off" : "Every \(model.settings.presenceChimeMinutes)m",
                range: 0...30,
                step: 5,
                binding: settingsBinding(\.presenceChimeMinutes)
            )
            StepperRow(
                title: "Overtime reminder",
                value: model.settings.overtimeReminderMinutes == 0 ? "Off" : "Every \(model.settings.overtimeReminderMinutes)m",
                range: 0...10,
                step: 1,
                binding: settingsBinding(\.overtimeReminderMinutes)
            )
            ToggleRow(
                title: "Pause when I'm away",
                subtitle: "Stop counting when your Mac is locked or asleep, or sits idle while a timer runs over. A block still counts up to its bell, and you can count the rest when you're back.",
                binding: settingsBinding(\.pauseWhenAway)
            )
            if model.settings.pauseWhenAway {
                StepperRow(
                    title: "Away after",
                    value: "\(model.settings.awayMinutes) min",
                    range: 5...30,
                    step: 5,
                    binding: settingsBinding(\.awayMinutes)
                )
            }
            ToggleRow(
                title: "Overtime alert",
                subtitle: "Flash the time red once a timer runs over",
                binding: settingsBinding(\.overtimeAlert)
            )
            ToggleRow(
                title: "Glow when time's up",
                subtitle: "The screen edges glow when a block or break ends and at each overtime reminder. No sound. Shows over full-screen apps.",
                binding: settingsBinding(\.screenGlow)
            )
            if model.settings.screenGlow {
                HStack {
                    Spacer()
                    Button("Preview") {
                        var color: NSColor?
                        if model.settings.menuBarColor != "auto" {
                            let rgb = RGB(hex: model.settings.menuBarColor)
                            color = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
                        }
                        ScreenGlow.shared.show(color: color)
                    }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications that stay")
                        .font(.system(size: 12, weight: .medium))
                    Text("In macOS, set Pomofocus notifications to Persistent so they stay until you close them.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Open Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=org.pomodorononna.app")
                        ?? URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rate your focus")
                        .font(.system(size: 12, weight: .medium, design: .default))
                    Text("Asks how focused you felt")
                        .font(.system(size: 10, design: .default))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Picker("Rate your focus", selection: settingsBinding(\.rateFocus)) {
                    ForEach(RatingTiming.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            ToggleRow(
                title: "Celebrate sessions",
                subtitle: "A short animation and a summary when you end a session",
                binding: settingsBinding(\.celebrateSessions)
            )
            if model.settings.celebrateSessions {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Celebration style")
                            .font(.system(size: 12, weight: .medium))
                        Text("What plays when a session ends")
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    Spacer()
                    Picker("Celebration style", selection: settingsBinding(\.celebrationStyle)) {
                        ForEach(CelebrationStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
            ToggleRow(
                title: "Keep tasks simple",
                subtitle: "Tasks shows only what's next, and nudges you to start after a few minutes of planning",
                binding: settingsBinding(\.simpleTasks)
            )
            ToggleRow(
                title: "Show the time",
                subtitle: "A clock above the timer",
                binding: $showsClock
            )
            FocusQuietSettingsRow()
            ToggleRow(
                title: "Daily check-in",
                subtitle: "Ask how you're feeling once a day. Your mood shows in Progress → Mood, and you can check in there too",
                binding: $dailyCheckIn
            )
            ToggleRow(
                title: "Timer cues",
                subtitle: "Sounds when a block starts, pauses or ends",
                binding: settingsBinding(\.playSounds)
            )
            ToggleRow(
                title: "Reset captions",
                subtitle: "Show what the voice says",
                binding: settingsBinding(\.resetCaptions)
            )
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Under a reset")
                        .font(.system(size: 12, weight: .medium))
                    Text("What plays under the voice in Breathe, Settle and Ease back in")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Picker("Under a reset", selection: settingsBinding(\.resetAmbience)) {
                    ForEach(ResetAmbience.allCases.filter(\.isAvailable)) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .frame(width: 170)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup")
                        .font(.system(size: 12, weight: .medium))
                    Text("Choose again how you like to work")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer(minLength: 12)
                Button("Run setup again") { model.updateSettings { $0.hasCompletedOnboarding = false } }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
            }
        }
    }

    private var calendarSettings: some View {
        SettingsCard(title: "Calendar", icon: "calendar") {
            calendarConnectionStatus
            ToggleRow(
                title: "Calendar overlay",
                subtitle: "Show your events on the day timeline",
                binding: Binding(
                    get: { model.settings.showCalendarEvents },
                    set: { enabled in
                        model.updateSettings { $0.showCalendarEvents = enabled }
                        if enabled, calendarStore.access == .notDetermined {
                            calendarStore.requestAccess()
                        }
                    }
                )
            )
            calendarAccessDetail
        }
    }

    private var widgetSettings: some View {
        SettingsCard(title: "Desktop widget", icon: "rectangle.3.group") {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(NonnaTheme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Small, medium and large")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NonnaTheme.ink)
                    Text("A live timer with a progress band.")
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider().overlay(NonnaTheme.line)

            VStack(alignment: .leading, spacing: 7) {
                Label("Right-click the desktop, or open Notification Center", systemImage: "1.circle")
                Label("Choose Edit Widgets and search for Pomofocus", systemImage: "2.circle")
                Label("Choose a size and add it to the desktop or sidebar", systemImage: "3.circle")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
    }

    private var calendarConnectionStatus: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(calendarStatusColor.opacity(0.14))
                Image(systemName: calendarStatusIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(calendarStatusColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(calendarStatusTitle)
                    .font(.system(size: 12, weight: .semibold))
                Text(calendarStatusSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(calendarStatusColor)
                .frame(width: 6, height: 6)
                .shadow(color: calendarStatusColor.opacity(0.5), radius: 4)
        }
        .padding(10)
        .background(NonnaTheme.sunken.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(NonnaTheme.line, lineWidth: 0.8)
        }
    }

    private var calendarStatusTitle: String {
        switch calendarStore.access {
        case .notDetermined: "Calendar setup needed"
        case .denied: "Calendar access is off"
        case .granted: "Calendar connected"
        }
    }

    private var calendarStatusSubtitle: String {
        switch calendarStore.access {
        case .notDetermined: "Allow access to show events on the timeline"
        case .denied: "Reconnect in macOS Privacy & Security"
        case .granted:
            calendarStore.calendars.isEmpty
                ? "Connected, no calendars found"
                : "Connected, \(calendarStore.calendars.count) calendar\(calendarStore.calendars.count == 1 ? "" : "s")"
        }
    }

    private var calendarStatusIcon: String {
        switch calendarStore.access {
        case .notDetermined: "calendar.badge.exclamationmark"
        case .denied: "calendar.badge.minus"
        case .granted: "calendar.badge.checkmark"
        }
    }

    private var calendarStatusColor: Color {
        switch calendarStore.access {
        case .notDetermined: NonnaTheme.gold
        case .denied: NonnaTheme.alert
        case .granted: NonnaTheme.sage
        }
    }

    @ViewBuilder
    private var calendarAccessDetail: some View {
        switch calendarStore.access {
        case .notDetermined:
            calendarNote("macOS asks for full access because it has no read-only option. Pomofocus only reads events.")
            Button {
                calendarStore.requestAccess()
            } label: {
                Label(calendarStore.isRequestingAccess ? "Requesting access…" : "Allow calendar access", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
            .disabled(calendarStore.isRequestingAccess)
            if let accessError = calendarStore.accessError {
                calendarNote(accessError)
                    .foregroundStyle(NonnaTheme.alert)
            }
        case .denied:
            calendarNote("Turn on full access for Pomofocus under Privacy & Security, then come back.")
            Button {
                calendarStore.openPrivacySettings()
            } label: {
                Label("Open Privacy Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
        case .granted:
            if calendarStore.calendars.isEmpty {
                calendarNote("Add an account, like Google, in System Settings under Internet Accounts.")
            } else {
                calendarNote("Calendars from every account on this Mac show here, Google included.")
                ForEach(calendarStore.calendars) { info in
                    CalendarToggleRow(info: info, isVisible: calendarVisibilityBinding(for: info.id))
                }
            }
        }
    }

    private func calendarNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .default))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func calendarVisibilityBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !model.settings.hiddenCalendarIDs.contains(id) },
            set: { visible in
                model.updateSettings { settings in
                    if visible {
                        settings.hiddenCalendarIDs.removeAll { $0 == id }
                    } else if !settings.hiddenCalendarIDs.contains(id) {
                        settings.hiddenCalendarIDs.append(id)
                    }
                }
            }
        )
    }

    private var privacySettings: some View {
        SettingsCard(title: "Your data", icon: "lock.shield") {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(NonnaTheme.sage)
                Text("Sessions are saved in one readable JSON file in Application Support. Nothing leaves this Mac. The only network request is the update check, which asks GitHub for the newest version number. Calendar events are only read.")
                    .font(.system(size: 12, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await model.revealDataFile() }
            } label: {
                Label("Show local data file", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
        }
    }

    private func settingsBinding<Value>(_ keyPath: WritableKeyPath<NonnaSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// A Settings section that folds to its heading, so the page is a short list to scan
/// rather than one long scroll. Each remembers whether it was left open; all start closed.
struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    /// A line shown beside the heading while it's closed, such as the current value.
    let summary: String?
    @ViewBuilder let content: Content
    @AppStorage private var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, icon: String, summary: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.summary = summary
        self.content = content()
        _open = AppStorage(wrappedValue: false, "settings.open.\(title)")
    }

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 17) {
                Button {
                    withAnimation(reduceMotion ? nil : NonnaMotion.dismiss) { open.toggle() }
                } label: {
                    HStack(spacing: 10) {
                        Label(title, systemImage: icon)
                            .font(.system(size: 17, weight: .bold, design: .default))
                        Spacer(minLength: 8)
                        if !open, let summary {
                            Text(summary)
                                .font(.system(size: 11))
                                .foregroundStyle(NonnaTheme.secondaryInk)
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .rotationEffect(.degrees(open ? 0 : -90))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(open ? "Collapse" : "Expand")
                .accessibilityValue(open ? "Expanded" : "Collapsed")

                if open {
                    Divider().overlay(NonnaTheme.line)
                        .transition(.opacity)
                    // Opening, the settings ease down into place; closing, they fade quickly
                    // while the card folds up around them.
                    content
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: -8)).animation(.easeOut(duration: 0.32).delay(0.06)),
                            removal: .opacity.animation(.easeIn(duration: 0.14))))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CalendarToggleRow: View {
    let info: CalendarInfo
    @Binding var isVisible: Bool

    var body: some View {
        Toggle(isOn: $isVisible) {
            HStack(spacing: 9) {
                Circle()
                    .fill(info.color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title)
                        .font(.system(size: 12, weight: .medium, design: .default))
                        .lineLimit(1)
                    if !info.sourceTitle.isEmpty {
                        Text(info.sourceTitle)
                            .font(.system(size: 11, design: .default))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct StepperRow: View {
    let title: String
    let value: String
    let range: ClosedRange<Int>
    let step: Int
    @Binding var binding: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
            Spacer()
            Stepper(value: $binding, in: range, step: step) {
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(minWidth: 70, alignment: .trailing)
            }
            .fixedSize()
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var binding: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                Text(subtitle)
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $binding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

/// "What should we call you?", used for the greeting on the timer.
private struct NameSettingsRow: View {
    @AppStorage("displayName") private var displayName = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 16))
                .foregroundStyle(NonnaTheme.terracotta)
            VStack(alignment: .leading, spacing: 2) {
                Text("What should we call you?")
                    .font(.system(size: 12, weight: .medium))
                Text("Shown as a greeting on the timer")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            TextField("Your first name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .padding(16)
        .background(NonnaTheme.raisedPaper.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}

/// Send Pomofocus to a friend: the website has the download and a three-step install guide.
private struct ShareSettingsCard: View {
    private static let site = URL(string: "https://cryptochefa.github.io/pomofocus-mac/#download")!
    @State private var copied = false

    var body: some View {
        SettingsCard(title: "Share Pomofocus", icon: "square.and.arrow.up") {
            Text("Send friends the website. It has the download and install steps.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ShareLink(item: Self.site, subject: Text("Pomofocus"), message: Text("A free focus timer for Mac:")) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NonnaButtonStyle())
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.site.absoluteString, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "link")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
        }
    }
}

/// How the menu-bar item looks: the timer chip, three bars in a colour you pick, or your
/// own icon, with or without the time beside it.
private struct MenuBarSettingsCard: View {
    @Environment(AppModel.self) private var model
    @State private var iconError: String?

    private static let swatches: [(name: String, hex: String)] = [
        ("Red", "FF3B30"), ("White", "FFFFFF"), ("Black", "000000"),
    ]

    private var settings: NonnaSettings { model.settings }
    private var style: MenuBarStyle { MenuBarStyle(rawValue: settings.menuBarStyle) ?? .chip }

    var body: some View {
        SettingsCard(title: "Menu bar", icon: "menubar.rectangle",
                     summary: settings.showInMenuBar ? style.title : "Hidden") {
            ToggleRow(
                title: "Show in the menu bar",
                subtitle: "Click it to open the timer panel",
                binding: binding(\.showInMenuBar)
            )
            if settings.showInMenuBar {
                Divider().overlay(NonnaTheme.line)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(MenuBarStyle.allCases) { option in styleTile(option) }
                }
                if style == .bars || style == .minimal { colorRow }
                if style == .icon { iconRows }
                if style != .chip { textRow }
            }
        }
    }

    // MARK: Style

    private func styleTile(_ option: MenuBarStyle) -> some View {
        let selected = option == style
        return Button {
            model.updateSettings { $0.menuBarStyle = option.rawValue }
        } label: {
            VStack(spacing: 8) {
                preview(option)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(NonnaTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(option.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected ? NonnaTheme.ink : NonnaTheme.secondaryInk)
            }
            .padding(8)
            .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: selected ? 1.5 : 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What the menu bar writes: the time left or a percentage. Minimal always shows one.
    private var textRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(style == .minimal ? "Show" : "Beside it")
                    .font(.system(size: 12, weight: .medium))
                Text(textMode == "percent" ? "How far through the block, like 62%" : textMode == "time" ? "Time left, like 18:42" : "Only the \(style == .icon ? "icon" : "bars")")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Picker("Show", selection: Binding(
                get: { textMode },
                set: { mode in model.updateSettings { $0.menuBarText = mode } }
            )) {
                if style != .minimal { Text("Nothing").tag("none") }
                Text("Time left").tag("time")
                Text("Percent").tag("percent")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    /// The text setting as the current style uses it: Minimal can't show nothing.
    private var textMode: String {
        style == .minimal && settings.menuBarText == "none" ? "time" : settings.menuBarText
    }

    /// A still of each look, part-way through a block.
    @ViewBuilder
    private func preview(_ option: MenuBarStyle) -> some View {
        let mode = option == .minimal && settings.menuBarText == "none" ? "time" : settings.menuBarText
        let sample: String? = mode == "percent" ? "62%" : mode == "time" ? "18:42" : nil
        let time = option == style || option == .minimal ? sample : nil
        switch option {
        case .chip:
            Image(nsImage: MenuBarGlyph.image(text: "18:42", fill: 0.62, tone: .focus))
        case .bars, .icon:
            let image = MenuBarMark.image(
                bars: MenuBarMark.Bars(levels: [1, 1, 0.45], alpha: 1),
                color: barColor,
                icon: option == .icon ? MenuBarIconStore.image : nil,
                iconFollowsMenuBar: settings.menuBarIconTemplate,
                text: time
            )
            Image(nsImage: image)
                .foregroundStyle(NonnaTheme.ink)
        case .minimal:
            Image(nsImage: MenuBarMark.image(
                bars: MenuBarMark.Bars(levels: [], alpha: 1), color: barColor, icon: nil,
                iconFollowsMenuBar: false, text: time ?? "18:42", showsMark: false))
                .foregroundStyle(NonnaTheme.ink)
        }
    }

    // MARK: Colour

    private var barColor: NSColor? {
        guard settings.menuBarColor != "auto" else { return nil }
        let rgb = RGB(hex: settings.menuBarColor)
        return NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1)
    }

    private var colorRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Colour")
                    .font(.system(size: 12, weight: .medium))
                Text(settings.menuBarColor == "auto" ? "Matches the menu bar, light or dark" : (style == .minimal ? "The text's colour, and the glow's" : "The bars' colour, and the glow's"))
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            swatch(hex: "auto", name: "Match the menu bar") {
                Circle().fill(LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            ForEach(Self.swatches, id: \.hex) { swatch in
                self.swatch(hex: swatch.hex, name: swatch.name) { Circle().fill(Color(hex: swatch.hex)) }
            }
            ColorPicker("Any colour", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .help("Any colour")
        }
    }

    private func swatch<Fill: View>(hex: String, name: String, @ViewBuilder fill: () -> Fill) -> some View {
        let selected = settings.menuBarColor.uppercased() == hex.uppercased()
        return Button {
            model.updateSettings { $0.menuBarColor = hex }
        } label: {
            fill()
                .frame(width: 18, height: 18)
                .overlay { Circle().stroke(NonnaTheme.strongLine, lineWidth: 0.8) }
                .padding(3)
                .overlay { Circle().stroke(selected ? NonnaTheme.terracotta : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The colour well: shows the chosen colour, and picking one makes it the bars' colour.
    private var customColor: Binding<Color> {
        Binding(
            get: { settings.menuBarColor == "auto" ? NonnaTheme.terracotta : Color(hex: settings.menuBarColor) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let hex = RGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent).hex
                model.updateSettings { $0.menuBarColor = hex }
            }
        )
    }

    // MARK: Your icon

    @ViewBuilder
    private var iconRows: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Icon")
                    .font(.system(size: 12, weight: .medium))
                Text(iconError ?? (MenuBarIconStore.image == nil
                    ? "A PNG, JPEG, HEIC or PDF. The bars show until you choose one."
                    : "Shown at menu bar size. Square pictures work best."))
                    .font(.system(size: 10))
                    .foregroundStyle(iconError == nil ? NonnaTheme.secondaryInk : NonnaTheme.alert)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if MenuBarIconStore.image != nil {
                Button("Remove") {
                    MenuBarIconStore.remove()
                    refreshMenuBar()
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            Button(MenuBarIconStore.image == nil ? "Choose Image…" : "Change…") { chooseIcon() }
                .buttonStyle(NonnaButtonStyle())
        }
        if MenuBarIconStore.image != nil {
            ToggleRow(
                title: "Match the menu bar colour",
                subtitle: "For one-colour icons: white on a dark menu bar, black on a light one",
                binding: binding(\.menuBarIconTemplate)
            )
        }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Menu Bar Icon"
        panel.prompt = "Use as Icon"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .pdf, .gif, .bmp]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try MenuBarIconStore.save(from: url)
            iconError = nil
        } catch {
            iconError = "That file couldn't be read as a picture. Try a PNG or JPEG."
        }
        refreshMenuBar()
    }

    /// The menu-bar item redraws on timer changes; a new icon isn't one, so nudge it.
    private func refreshMenuBar() {
        model.menuPulse.tick &+= 1
        model.updateSettings { _ in }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<NonnaSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { newValue in model.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }
}
