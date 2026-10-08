import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @EnvironmentObject private var calendarStore: CalendarStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(
                    eyebrow: "Make it yours",
                    title: "Settings",
                    subtitle: "No account, telemetry, cloud service, or hidden data collection."
                )

                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 18) {
                        timerSettings
                        rhythmSettings
                    }
                    VStack(spacing: 18) {
                        experienceSettings
                        widgetSettings
                        calendarSettings
                        privacySettings
                    }
                }
            }
            .padding(30)
        }
    }

    private var timerSettings: some View {
        SettingsCard(title: "Timer", icon: "timer") {
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
        SettingsCard(title: "Rhythm", icon: "chart.line.uptrend.xyaxis") {
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
                subtitle: "Useful for a strict Pomodoro cycle",
                binding: settingsBinding(\.autoStartBreaks)
            )
            ToggleRow(
                title: "Start focus automatically",
                subtitle: "Begin after a break ends",
                binding: settingsBinding(\.autoStartFocus)
            )
        }
    }

    private var experienceSettings: some View {
        SettingsCard(title: "Experience", icon: "sparkles") {
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
                subtitle: "3 rounds · 4 sec in · 6 sec out",
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
                title: "Overtime alert",
                subtitle: "Flash the time red once a timer runs over",
                binding: settingsBinding(\.overtimeAlert)
            )
            ToggleRow(
                title: "Celebrate sessions",
                subtitle: "Confetti and a breakdown of the sitting when you end a session",
                binding: settingsBinding(\.celebrateSessions)
            )
            ToggleRow(
                title: "Timer cues",
                subtitle: "Gentle cues for starts, pauses, and endings",
                binding: settingsBinding(\.playSounds)
            )
        }
    }

    private var calendarSettings: some View {
        SettingsCard(title: "Calendar", icon: "calendar") {
            calendarConnectionStatus
            ToggleRow(
                title: "Calendar overlay",
                subtitle: "Read-only overlay on the day timeline",
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
                    Text("Small, medium, and large")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NonnaTheme.ink)
                    Text("A live black-and-white timer with one gold progress band. Your focus data stays on this Mac.")
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
                    .font(.system(size: 9))
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
        case .notDetermined: "Allow access once to keep the timeline populated"
        case .denied: "Reconnect in macOS Privacy & Security"
        case .granted:
            calendarStore.calendars.isEmpty
                ? "Connected · no calendars found"
                : "Connected · \(calendarStore.calendars.count) calendar\(calendarStore.calendars.count == 1 ? "" : "s")"
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
            calendarNote("macOS only offers full calendar access or none, so its prompt says \"full access\". Pomofocus only reads events. It has no code that creates, edits, or deletes them.")
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
            calendarNote("Calendar access is off. Turn on full access for Pomofocus under Privacy & Security, then come back. Events are only ever read.")
            Button {
                calendarStore.openPrivacySettings()
            } label: {
                Label("Open Privacy Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NonnaButtonStyle(prominent: false))
        case .granted:
            if calendarStore.calendars.isEmpty {
                calendarNote("No calendars found. Add your Google account in System Settings under Internet Accounts and it will appear here.")
            } else {
                calendarNote("Any account added to macOS shows up here, Google included. Events are read from your Mac and never leave it.")
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
                Text("Sessions are written to one readable JSON file in your Application Support folder. Pomofocus contains no networking code, and calendar events are only read, never changed.")
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

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        NonnaCard {
            VStack(alignment: .leading, spacing: 17) {
                Label(title, systemImage: icon)
                    .font(.system(size: 17, weight: .bold, design: .default))
                Divider().overlay(NonnaTheme.line)
                content
            }
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
                            .font(.system(size: 9, design: .default))
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
        Toggle(isOn: $binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .default))
                Text(subtitle)
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .toggleStyle(.switch)
    }
}
