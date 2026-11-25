import SwiftUI

/// Every "I've lost it" moment opens this: the coach's pick, and five quiet alternatives.
struct ResetSheet: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    @State private var dumping = false
    @State private var hovered: Option?

    enum Option: String, CaseIterable, Identifiable {
        case walk, brainDump, oneMinute, settle, comingBack, rest
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .walk: "figure.walk"
            case .brainDump: "square.and.pencil"
            case .oneMinute: "wind"
            case .settle: "leaf"
            case .comingBack: "arrow.uturn.backward"
            case .rest: "moon.zzz"
            }
        }

        var title: String {
            switch self {
            case .walk: "Walk"
            case .brainDump: "Write it out"
            case .oneMinute: "Breathe"
            case .settle: "Settle"
            case .comingBack: "Ease back in"
            case .rest: "Rest"
            }
        }
    }

    /// The coach's pick: from how the last block went, or a breath by default.
    private var suggested: Option {
        switch model.breakSuggestion?.kind {
        case .some(.move): return .walk
        case .some(.unload): return .brainDump
        case .some(.callIt): return .rest
        case .none:
            let today = FocusSession.mergedBlocks(model.sessions.filter { Calendar.current.isDateInToday($0.startedAt) })
                .sorted { $0.startedAt < $1.startedAt }
            switch today.last?.focusRating {
            case 1: return .brainDump
            case 2: return .walk
            default: return .oneMinute
            }
        }
    }

    var body: some View {
        Group {
            if dumping {
                BrainDumpSheet(onClose: onClose)
            } else {
                choices
            }
        }
        .background(NonnaTheme.cream)
    }

    private var choices: some View {
        let pick = suggested
        return VStack(spacing: 26) {
            HStack {
                Text("Reset")
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(NonnaTheme.secondaryInk)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
            }

            Button { run(pick) } label: {
                VStack(spacing: 12) {
                    Image(systemName: pick.icon)
                        .font(.system(size: 34, weight: .light))
                    Text(pick.title)
                        .font(.system(size: 18, weight: .medium))
                }
                .foregroundStyle(NonnaTheme.sage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 34)
                .background(NonnaTheme.sage.opacity(hovered == pick ? 0.18 : 0.11), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .onHover { hovered = $0 ? pick : nil }

            HStack(spacing: 10) {
                ForEach(Option.allCases.filter { $0 != pick }) { option in
                    Button { run(option) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: option.icon)
                                .font(.system(size: 17, weight: .light))
                            Text(option.title)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(hovered == option ? NonnaTheme.ink : NonnaTheme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NonnaTheme.raisedPaper.opacity(hovered == option ? 1 : 0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? option : nil }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: hovered)
        .padding(30)
        .frame(width: 480)
    }

    private func run(_ option: Option) {
        switch option {
        case .brainDump:
            dumping = true
        case .walk:
            if model.phase == .focus, model.status != .idle { model.startBreak() }
            onClose()
        case .rest:
            model.endSession()
            onClose()
        case .oneMinute, .settle, .comingBack:
            onClose()
            let reset: FocusReset = option == .oneMinute ? .oneMinute : option == .settle ? .settle : .comingBack
            // After the sheet has gone: the reset takes over the whole window.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                model.startQuickReset(reset)
            }
        }
    }
}

/// On the break after a rough block: one line from the coach and the way into Reset.
struct ResetNudge: View {
    let text: String
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wind")
                .foregroundStyle(NonnaTheme.sage)
            Text(text)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button("Reset…", action: onOpen)
                .buttonStyle(NonnaButtonStyle(color: NonnaTheme.sage))
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NonnaTheme.sage.opacity(0.1))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.sage.opacity(0.45), lineWidth: 0.8) }
        }
    }
}
