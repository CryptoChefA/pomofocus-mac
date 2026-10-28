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
        NonnaCard {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Appearance", systemImage: "paintpalette")
                        .font(.system(size: 17, weight: .bold))
                    Spacer()
                    Text("Changes apply instantly, everywhere: windows, menu bar panel, Cinema and celebrations.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Divider().overlay(NonnaTheme.line)
                ThemePicker()
            }
        }
    }
}

// MARK: - Welcome

/// Shown once on a fresh install: pick a look, then optionally start a focus plan.
/// First launch: a few calm questions, one per page, in the style of a Mac setup assistant.
/// Few words, centred, in the theme's own colours, type and buttons.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("displayName") private var displayName = ""
    @State private var page = 0
    @State private var appeared = false
    @FocusState private var nameFocused: Bool
    let onBuildPlan: () -> Void

    private static let pageCount = 4
    private var name: String { displayName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: namePage.transition(pageTransition)
                case 1: goalPage.transition(pageTransition)
                case 2: themePage.transition(pageTransition)
                default: planPage.transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 16) {
                if page < Self.pageCount - 1 {
                    Button("Continue") { go(to: page + 1) }
                        .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Build my focus plan") {
                        model.completeOnboarding()
                        onBuildPlan()
                    }
                    .buttonStyle(OnboardingButtonStyle(color: NonnaTheme.terracotta))
                    .keyboardShortcut(.defaultAction)
                    Button("Not now") { model.completeOnboarding() }
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
            }
            .overlay(alignment: .leading) {
                if page > 0 {
                    Button { go(to: page - 1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .help("Back")
                }
            }
        }
        .padding(48)
        .frame(width: 760, height: 600)
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
        }
    }

    // Only opacity and a short slide: cheap to draw, calm to watch.
    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity.combined(with: .offset(x: -24)))
    }

    private func go(to target: Int) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.08)) { page = target }
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
        }
    }

    private var themePage: some View {
        VStack(spacing: 32) {
            title("Choose a look.")
            ThemePicker()
                .opacity(appeared ? 1 : 0)
        }
    }

    private var planPage: some View {
        VStack(spacing: 18) {
            title(name.isEmpty ? "Want a focus plan?" : "Want a focus plan, \(name)?")
            Text("Eight quick questions. A plan that grows with you.")
                .font(.system(size: 15))
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
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
