import AppKit
import SwiftUI

// MARK: - Picker

/// The grid of looks, shared by Settings and the welcome screen. Picking one restyles
/// the whole app immediately, with a soft crossfade.
struct ThemePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var columns = 5
    @Environment(\.compactLayout) private var compact

    /// nil while a theme from a code is in use.
    private var selected: ThemeChoice? { ThemeChoice(rawValue: model.settings.themeID) }
    @State private var code = ""
    @State private var codeMessage: (ok: Bool, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: compact ? 3 : columns), spacing: 14) {
                // Limited editions show up in their season, or while they're in use.
                ForEach(ThemeChoice.allCases.filter { $0.isAvailable() || $0 == selected }) { choice in
                    ThemeSwatchButton(choice: choice, custom: model.settings.customTheme, isSelected: selected == choice) {
                        ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                            model.updateSettings { $0.themeID = choice.rawValue }
                        }
                    }
                }
                // Themes added from codes, rare ones first.
                ForEach(model.settings.savedThemes.sorted { $0.isRare && !$1.isRare }) { theme in
                    SavedThemeSwatch(theme: theme, isSelected: model.settings.themeID == theme.themeID) {
                        ThemeCrossfade.perform(reduceMotion: reduceMotion) {
                            model.updateSettings { $0.themeID = theme.themeID }
                        }
                    }
                }
            }
            if selected == .custom {
                CustomThemeEditor()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            codeField
        }
        .animation(reduceMotion ? nil : NonnaMotion.selection, value: selected)
    }
}

extension ThemePicker {
    /// Paste a code from a friend, or a rare one from the developer.
    var codeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "ticket")
                    .foregroundStyle(NonnaTheme.secondaryInk)
                TextField("Paste a theme code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCode)
                Button("Add", action: addCode)
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let codeMessage {
                Text(codeMessage.text)
                    .font(.system(size: 11))
                    .foregroundStyle(codeMessage.ok ? NonnaTheme.sage : NonnaTheme.alert)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    func addCode() {
        let result = model.addTheme(fromCode: code)
        codeMessage = (result.ok, result.message)
        if result.ok { code = "" }
    }
}

/// A theme from a code: a preview, its name and note, and a Rare or Shared tag.
private struct SavedThemeSwatch: View {
    @Environment(AppModel.self) private var model
    let theme: SharedTheme
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                ThemeMiniPreview(theme: ResolvedTheme(theme.spec.palette))
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? NonnaTheme.terracotta : (theme.isRare ? Color(hex: "C9A55A") : NonnaTheme.line),
                                    lineWidth: isSelected ? 2 : (theme.isRare ? 1.2 : 0.8))
                    }
                    .overlay(alignment: .topLeading) {
                        Label(theme.isRare ? "Rare" : "Shared", systemImage: theme.isRare ? "seal.fill" : "person.2")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.isRare ? Color(hex: "1A1408") : .white)
                            .padding(.horizontal, 7)
                            .frame(height: 18)
                            .background(theme.isRare ? Color(hex: "D9B86A") : Color.black.opacity(0.55), in: Capsule())
                            .padding(7)
                    }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(theme.note ?? "From a theme code")
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(NonnaTheme.terracotta)
                    }
                }
            }
            .scaleEffect(hovering && !isSelected ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .help(theme.note ?? theme.name)
        .contextMenu {
            if !theme.isRare {
                Button("Copy code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ThemeCodes.code(for: theme), forType: .string)
                }
            }
            Button("Remove", role: .destructive) { model.removeSavedTheme(theme.id) }
        }
        .accessibilityLabel("\(theme.name), \(theme.isRare ? "rare" : "shared") theme")
    }
}

private struct ThemeSwatchButton: View {
    let choice: ThemeChoice
    let custom: CustomThemeSpec
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                preview
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: isSelected ? 2 : 0.8)
                    }
                    .shadow(color: isSelected ? NonnaTheme.terracotta.opacity(0.3) : .clear, radius: 10)
                    .overlay(alignment: .topLeading) {
                        if choice.isLimitedEdition {
                            Text("Limited")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 18)
                                .background(Color(hex: "B4501E"), in: Capsule())
                                .padding(7)
                                .help("A limited edition, here for the fall")
                        }
                    }
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(choice.title).font(.system(size: 12, weight: .semibold))
                        Text(choice.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NonnaTheme.terracotta)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .scaleEffect(hovering && !isSelected ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .accessibilityLabel("\(choice.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch choice {
        case .system:
            ZStack {
                ThemeMiniPreview(theme: ResolvedTheme(.ivory))
                ThemeMiniPreview(theme: ResolvedTheme(.obsidian))
                    .mask {
                        GeometryReader { proxy in
                            Path { path in
                                path.move(to: CGPoint(x: proxy.size.width * 0.62, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                                path.addLine(to: CGPoint(x: proxy.size.width * 0.38, y: proxy.size.height))
                                path.closeSubpath()
                            }
                        }
                    }
            }
        case .custom:
            ThemeMiniPreview(theme: ResolvedTheme(custom.palette))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "paintbrush.pointed.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: custom.palette.onAccent))
                        .frame(width: 22, height: 22)
                        .background(Color(hex: custom.accent), in: Circle())
                        .padding(7)
                }
        default:
            ThemeMiniPreview(theme: ResolvedTheme(choice.palette ?? .obsidian))
        }
    }
}

/// A tiny picture of the app in a given palette: sidebar, card, dial, button.
struct ThemeMiniPreview: View {
    let theme: ResolvedTheme

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.sunken)
                .frame(width: 16)
                .overlay(alignment: .top) {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(theme.ink).frame(width: 7, height: 7)
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(theme.secondaryInk.opacity(0.6)).frame(width: 4, height: 4) }
                    }
                    .padding(.top, 8)
                }
            ZStack {
                theme.background
                RadialGradient(colors: [theme.accent.opacity(0.18), .clear], center: .topTrailing, startRadius: 2, endRadius: 90)
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(theme.raised)
                        Circle().stroke(theme.line, lineWidth: 1)
                        Circle()
                            .trim(from: 0, to: 0.62)
                            .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1)
                        Circle().fill(theme.accent.opacity(0.22)).padding(9)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(theme.ink).frame(width: 40, height: 5)
                        Capsule().fill(theme.secondaryInk.opacity(0.7)).frame(width: 30, height: 4)
                        HStack(spacing: 4) {
                            Capsule().fill(theme.accent).frame(width: 24, height: 10)
                            Capsule().fill(theme.raised).overlay(Capsule().stroke(theme.line, lineWidth: 0.8)).frame(width: 18, height: 10)
                        }
                        HStack(spacing: 3) {
                            Circle().fill(theme.rest).frame(width: 5, height: 5)
                            Circle().fill(theme.longRest).frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Custom editor

private struct CustomThemeEditor: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    private var spec: CustomThemeSpec { model.settings.customTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Build your theme")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.shareCodeForCustomTheme(), forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        copied = false
                    }
                } label: {
                    Label(copied ? "Code copied" : "Share this theme", systemImage: copied ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.terracotta)
                .help("Copy a code anyone can paste into Settings to get this theme")
                Menu {
                    ForEach(ThemeChoice.allCases.filter { $0.palette != nil }) { choice in
                        Button(choice.title) {
                            guard let palette = choice.palette else { return }
                            update { $0 = CustomThemeSpec(isDark: palette.isDark, background: palette.background, accent: palette.accent, rest: palette.rest) }
                        }
                    }
                } label: {
                    Label("Start from…", systemImage: "square.on.square")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 18) {
                Picker("Base", selection: Binding(
                    get: { spec.isDark },
                    set: { dark in
                        update { custom in
                            let starter = dark ? CustomThemeSpec() : CustomThemeSpec.lightStarter
                            custom.isDark = dark
                            custom.background = starter.background
                        }
                    }
                )) {
                    Text("Dark").tag(true)
                    Text("Light").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)

                colorWell("Background", \.background)
                colorWell("Focus", \.accent)
                colorWell("Breaks", \.rest)
                Spacer(minLength: 0)
            }

            let contrast = RGB(hex: spec.accent).contrast(with: RGB(hex: spec.background))
            if contrast < 2.2 {
                Label("Your focus colour is hard to see on this background. Try something brighter or darker.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.alert)
            } else {
                Text("Surfaces, lines and text are derived for you, so every combination stays readable.")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        .padding(16)
        .background(NonnaTheme.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }

    private func colorWell(_ title: String, _ key: WritableKeyPath<CustomThemeSpec, String>) -> some View {
        HStack(spacing: 7) {
            ColorPicker(title, selection: Binding(
                get: { Color(hex: spec[keyPath: key]) },
                set: { color in
                    guard let hex = color.sRGBHex, hex != spec[keyPath: key] else { return }
                    update { $0[keyPath: key] = hex }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            Text(title).font(.system(size: 12))
        }
    }

    private func update(_ mutate: (inout CustomThemeSpec) -> Void) {
        model.updateSettings { mutate(&$0.customTheme) }
    }
}

extension Color {
    /// The colour as six-digit sRGB hex, for saving.
    var sRGBHex: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return RGB(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent)).hex
    }
}

// MARK: - Settings card

struct AppearanceSettingsCard: View {
    var body: some View {
        SettingsCard(title: "Appearance", icon: "paintpalette",
                     summary: ThemeChoice(rawValue: ThemeManager.shared.themeID)?.title ?? "Your own theme") {
            Text("Changes apply instantly, everywhere: windows, menu bar panel, Cinema and celebrations.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
            ThemePicker()
            GlassSetting()
            if ThemeManager.shared.themeID == ThemeChoice.london.rawValue {
                LondonWeatherSettings()
                    .transition(.opacity)
            }
        }
    }
}

/// The Glass slider: from solid paper to clear glass, for the timer, cards and panels.
private struct GlassSetting: View {
    private var glass: Double { ThemeManager.shared.glass }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Glass").font(.system(size: 12, weight: .medium))
                Text("Let the theme show through the timer, cards and panels.")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Text("Solid").font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
            Slider(value: Binding(get: { ThemeManager.shared.glass }, set: { ThemeManager.shared.glass = $0 }), in: 0...1)
                .frame(width: 180)
                .tint(NonnaTheme.terracotta)
                .accessibilityLabel("Glass")
                .accessibilityValue(glass < 0.01 ? "Solid" : "\(Int((glass * 100).rounded())) percent")
            Text("Glass").font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// The London theme's weather: rain on or off, and a storm on top of it.
private struct LondonWeatherSettings: View {
    @AppStorage(LondonWeather.rainKey) private var rain = true
    @AppStorage(LondonWeather.stormKey) private var storm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("London weather")
                .font(.system(size: 13, weight: .semibold))
            row("Rain", "Rain falling over the river, rings on the water.", $rain)
            row("Storm", rain ? "Heavier, windier rain, with lightning in the clouds." : "Needs rain on.", $storm)
                .disabled(!rain)
                .opacity(rain ? 1 : 0.5)
        }
        .padding(16)
        .background(NonnaTheme.sunken.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private func row(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: binding)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

// MARK: - Welcome

/// Shown once on a fresh install, and again from Settings: name, how you like to work, a daily goal, a look,
/// a sound and a few extras, one calm question per page like a Mac setup assistant. Skip it any time.
/// Few words, centred, in the theme's own colours, type and buttons.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("displayName") private var displayName = ""
    @AppStorage(MoodPrompt.enabledKey) private var dailyCheckIn = true
    @AppStorage(QuietClock.enabledKey) private var showsClock = true
    @State private var page = 0
    @State private var appeared = false
    @State private var style: WorkStyle = .classic
    @State private var preview = AmbientSoundPlayer()
    @State private var previewStop: Task<Void, Never>?
    @FocusState private var nameFocused: Bool
    let onBuildPlan: () -> Void

    private static let pageCount = 7
    private var name: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The three ways to start, set on the second page.
    enum WorkStyle: CaseIterable {
        case classic, longer, buildUp

        var title: String {
            switch self {
            case .classic: "Classic"
            case .longer: "Longer blocks"
            case .buildUp: "Build up slowly"
            }
        }

        var detail: String {
            switch self {
            case .classic: "25 minutes of focus, 5 minutes off. The original Pomodoro."
            case .longer: "50 minutes of focus, 10 off. For when you get into a rhythm."
            case .buildUp: "Start where you are today and add five minutes as you go."
            }
        }

        var icon: String {
            switch self {
            case .classic: "timer"
            case .longer: "hourglass"
            case .buildUp: "chart.line.uptrend.xyaxis"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: namePage.transition(pageTransition)
                case 1: stylePage.transition(pageTransition)
                case 2: goalPage.transition(pageTransition)
                case 3: themePage.transition(pageTransition)
                case 4: soundPage.transition(pageTransition)
                case 5: extrasPage.transition(pageTransition)
                default: donePage.transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 16) {
                if page < Self.pageCount - 1 {
                    Button("Continue") { go(to: page + 1) }
                        .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                        .keyboardShortcut(.defaultAction)
                } else if style == .buildUp {
                    Button("Build my focus plan") { finish(buildPlan: true) }
                        .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                        .keyboardShortcut(.defaultAction)
                    Button("Not now") { finish(buildPlan: false) }
                        .buttonStyle(.plain)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                } else {
                    Button("Start focusing") { finish(buildPlan: false) }
                        .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                        .keyboardShortcut(.defaultAction)
                    Button("Or build a focus plan first") { finish(buildPlan: true) }
                        .buttonStyle(.plain)
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                HStack(spacing: 7) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                            .frame(width: index == page ? 18 : 6, height: 6)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement()
                .accessibilityLabel("Step \(page + 1) of \(Self.pageCount)")
            }
            .overlay(alignment: .leading) {
                if page > 0 {
                    Button { go(to: page - 1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .help("Back")
                    .accessibilityLabel("Back")
                }
            }
        }
        .padding(48)
        .frame(width: 760, height: 620)
        .overlay(alignment: .topTrailing) {
            if page < Self.pageCount - 1 {
                Button("Skip setup") { finish(buildPlan: false) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .padding(22)
                    .help("Use the usual settings. You can change everything later in Settings")
            }
        }
        .background {
            ZStack {
                NonnaTheme.cream
                RadialGradient(colors: [NonnaTheme.terracotta.opacity(0.16), .clear], center: .top, startRadius: 10, endRadius: 480)
            }
        }
        .foregroundStyle(NonnaTheme.ink)
        .tint(NonnaTheme.terracotta)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .interactiveDismissDisabled()
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.8)) { appeared = true }
            nameFocused = true
            // Run again from Settings, the choice shown is the one already in use.
            if model.data.focusPlan != nil { style = .buildUp }
            else if model.settings.focusMinutes >= 45 { style = .longer }
        }
        .onDisappear(perform: stopPreview)
    }

    // Only opacity and a short slide: cheap to draw, calm to watch.
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity.combined(with: .offset(x: -24)))
    }

    private func go(to target: Int) {
        if page == 4 { stopPreview() }
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.08)) { page = target }
    }

    private func finish(buildPlan: Bool) {
        stopPreview()
        model.completeOnboarding()
        if buildPlan { onBuildPlan() }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .regular, design: .serif))
            .tracking(-0.6)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
    }

    private func subtitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(NonnaTheme.secondaryInk)
            .multilineTextAlignment(.center)
    }

    // MARK: Pages

    private var namePage: some View {
        VStack(spacing: 40) {
            title(name.isEmpty ? "What should we call you?" : "Hello, \(name).")
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: name.isEmpty)
            TextField("", text: $displayName, prompt: Text("First name"))
                .textFieldStyle(.plain)
                .font(.system(size: 24))
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .onSubmit { go(to: 1) }
                .padding(.vertical, 12)
                .frame(width: 320)
                .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(nameFocused ? NonnaTheme.terracotta.opacity(0.6) : NonnaTheme.line, lineWidth: nameFocused ? 1.2 : 0.8)
                }
                .shadow(color: nameFocused ? NonnaTheme.terracotta.opacity(0.16) : .clear, radius: 10)
                .opacity(appeared ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.8).delay(0.2), value: appeared)
        }
    }

    private var stylePage: some View {
        VStack(spacing: 30) {
            title("How do you like to work?")
            HStack(spacing: 14) {
                ForEach(WorkStyle.allCases, id: \.self) { option in
                    OnboardingChoice(icon: option.icon, title: option.title, detail: option.detail, selected: style == option) {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) { choose(option) }
                    }
                }
            }
        }
    }

    private func choose(_ option: WorkStyle) {
        style = option
        model.updateSettings { settings in
            switch option {
            case .classic, .buildUp:
                settings.focusMinutes = 25
                settings.shortBreakMinutes = 5
                settings.longBreakMinutes = 20
            case .longer:
                settings.focusMinutes = 50
                settings.shortBreakMinutes = 10
                settings.longBreakMinutes = 30
            }
        }
    }

    private var goalPage: some View {
        let goal = model.settings.dailyGoalMinutes
        let options = [30, 60, 120, 180, 240]
        return VStack(spacing: 40) {
            title("How much focus makes a good day?")
            HStack(spacing: 10) {
                ForEach(options, id: \.self) { minutes in
                    let selected = goal == minutes
                    Button {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
                            model.updateSettings { $0.dailyGoalMinutes = minutes }
                        }
                    } label: {
                        Text(minutes.minutesString)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 92, height: 72)
                            .foregroundStyle(selected ? NonnaTheme.terracotta : NonnaTheme.ink)
                            .background(selected ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(selected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: selected ? 1.4 : 0.8)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            subtitle("A gentle target, not a test. Missing it doesn't break anything.")
        }
    }

    private var themePage: some View {
        VStack(spacing: 32) {
            title("Choose a look.")
            ThemePicker()
                .opacity(appeared ? 1 : 0)
        }
    }

    private var soundPage: some View {
        let current = model.settings.ambientSound
        let options: [AmbientSound] = [.off, .rain, .ocean, .ticking, .brownNoise]
        return VStack(spacing: 30) {
            title("What helps you focus?")
            HStack(spacing: 10) {
                ForEach(options) { sound in
                    let selected = current == sound
                    Button {
                        withAnimation(reduceMotion ? nil : NonnaMotion.selection) {
                            model.updateSettings { $0.ambientSound = sound }
                        }
                        play(sound)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: sound.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selected ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                            Text(sound == .off ? "Quiet" : sound.title)
                                .font(.system(size: 12, weight: .semibold))
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 112, height: 96)
                        .background(selected ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: selected ? 1.4 : 0.8)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            subtitle("Tap one to hear it. It plays under your focus blocks.")
            OnboardingToggle(title: "Timer cues", detail: "Gentle sounds when a block starts, pauses or ends",
                             isOn: Binding(get: { model.settings.playSounds }, set: { value in model.updateSettings { $0.playSounds = value } }))
                .frame(width: 440)
        }
    }

    private var extrasPage: some View {
        VStack(spacing: 26) {
            title("A few extras.")
            VStack(spacing: 12) {
                OnboardingToggle(title: "Daily check-in", detail: "Once a day, a quick \"How are you feeling?\"", isOn: $dailyCheckIn)
                OnboardingToggle(title: "Show the time", detail: "A small clock at the top of the timer", isOn: $showsClock)
                OnboardingToggle(title: "Keep tasks simple", detail: "Tasks shows what's next, not everything at once",
                                 isOn: Binding(get: { model.settings.simpleTasks }, set: { value in model.updateSettings { $0.simpleTasks = value } }))
                OnboardingToggle(title: "Timer in the menu bar", detail: "The countdown stays in view when the window is closed",
                                 isOn: Binding(get: { model.settings.showInMenuBar }, set: { value in model.updateSettings { $0.showInMenuBar = value } }))
            }
            .frame(width: 460)
        }
    }

    private var donePage: some View {
        VStack(spacing: 18) {
            title(name.isEmpty ? "You're all set." : "You're all set, \(name).")
            subtitle(style == .buildUp
                     ? "Next, eight quick questions to set up a plan that starts where you are."
                     : "You can change any of this later in Settings.")
        }
    }

    // MARK: Sound preview

    /// A few seconds of the sound, through a player of its own so the timer's is untouched.
    private func play(_ sound: AmbientSound) {
        previewStop?.cancel()
        guard sound != .off else { preview.stop(); return }
        preview.start(sound, volume: max(0.25, model.settings.ambientVolume))
        previewStop = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            preview.stop()
        }
    }

    private func stopPreview() {
        previewStop?.cancel()
        preview.stop()
    }
}

/// One of the setup's big choices: an icon, a name and a line under it.
private struct OnboardingChoice: View {
    let icon: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: 196, height: 160, alignment: .topLeading)
            .background(selected ? NonnaTheme.raisedPaper : NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: selected ? 1.4 : 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A switch with a name and a line of explanation, sized for the setup pages.
private struct OnboardingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.line, lineWidth: 0.8) }
    }
}

/// A wide capsule in the theme's accent, like a Mac setup assistant's main button.
private struct OnboardingButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(NonnaTheme.onAccent)
            .frame(width: 240, height: 40)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.3), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
