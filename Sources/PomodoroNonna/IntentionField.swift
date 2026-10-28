import AppKit
import SwiftUI

/// The "what are you working on?" line on the timer. The caret and border take the theme's
/// colour while typing stays calm; Return saves it with a soft glow and a check. Starting the
/// block is left to Begin focus.
struct IntentionField: View {
    enum Style { case pill, underline }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var style: Style = .pill
    @FocusState private var focused: Bool
    @State private var commits = 0
    @State private var justCommitted = false

    private var accent: Color { NonnaTheme.terracotta }

    var body: some View {
        @Bindable var model = model
        let field = ZStack(alignment: .leading) {
            if model.intention.isEmpty {
                Text(style == .pill ? "What are you working on?" : "e.g. Draft the opening section")
                    .foregroundStyle(NonnaTheme.secondaryInk.opacity(focused ? 0.45 : 0.62))
                    .allowsHitTesting(false)
            }
            TextField("", text: $model.intention, axis: style == .underline ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .foregroundStyle(justCommitted ? accent : NonnaTheme.ink)
                .lineLimit(style == .underline ? 1...3 : 1...1)
                // The text box fills the pill and takes clicks itself; a tap handler around
                // it used to swallow them, which could leave the field unclickable.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .focused($focused)
                .disabled(model.phase != .focus)
                .onSubmit { commit() }
                .onExitCommand { focused = false }
        }
        .tint(accent)

        Group {
            switch style {
            case .pill: pill(field)
            case .underline: underline(field)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: focused)
        .animation(.easeOut(duration: 0.35), value: justCommitted)
    }

    /// Return: saves the intention with a glow. It never starts the timer.
    private func commit() {
        focused = false
        let hasText = !model.intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            model.intention = model.intention.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reduceMotion { commits += 1 }
            justCommitted = true
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            Task {
                try? await Task.sleep(for: .seconds(1.1))
                justCommitted = false
            }
        }
        model.persistDraft()
    }

    // MARK: Styles

    private func pill(_ field: some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: justCommitted ? "checkmark.circle.fill" : "pencil.line")
                .font(.system(size: justCommitted ? 14 : 12, weight: .medium))
                .foregroundStyle(focused || justCommitted ? accent : NonnaTheme.secondaryInk.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            field
                .font(.system(size: 15, weight: .medium))
            hint
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 460)
        .frame(height: 46)
        .background(focused ? NonnaTheme.paper : NonnaTheme.raisedPaper.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .keyframeAnimator(initialValue: 0.0, trigger: commits) { content, glow in
            content
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(focused ? accent.opacity(0.55) : NonnaTheme.line, lineWidth: focused ? 1.2 : 0.8)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent.opacity(glow), lineWidth: 1.5)
                }
                .shadow(color: accent.opacity((focused ? 0.16 : 0) + 0.45 * glow), radius: 10 + 12 * glow)
        } keyframes: { _ in
            LinearKeyframe(1.0, duration: 0.06)
            CubicKeyframe(0.0, duration: 0.7)
        }
    }

    private func underline(_ field: some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                field
                    .font(.system(size: 18, weight: .medium))
                hint
            }
            ZStack(alignment: .leading) {
                Rectangle().fill(NonnaTheme.line).frame(height: 1)
                Rectangle()
                    .fill(accent)
                    .frame(height: 1.5)
                    .scaleEffect(x: focused || justCommitted ? 1 : 0, anchor: .leading)
                    .scaleEffect(x: 1, y: justCommitted ? 2 : 1)
                    .keyframeAnimator(initialValue: 0.0, trigger: commits) { bar, glow in
                        bar.shadow(color: accent.opacity(0.25 + 0.5 * glow), radius: 2 + 5 * glow)
                    } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 0.05)
                        CubicKeyframe(0.0, duration: 0.5)
                    }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.15), value: focused)
        }
    }

    @ViewBuilder
    private var hint: some View {
        if focused, !model.intention.isEmpty {
            Text("↩ Save")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(accent.opacity(0.12), in: Capsule())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .help("Press Return to save")
        }
    }
}
