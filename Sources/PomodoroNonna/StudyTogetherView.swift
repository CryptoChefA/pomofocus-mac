import SwiftUI

/// Start a group, or join one nearby. Friends' timers then follow the host's.
struct StudyTogetherSheet: View {
    @Environment(AppModel.self) private var model
    @AppStorage("displayName") private var displayName = ""
    let onClose: () -> Void
    private var group: StudyGroup { StudyGroup.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Study together")
                    .font(.system(size: 22, weight: .semibold))
                Text("For friends in the same room. One of you starts a group; the others join, and everyone's timer follows: the same blocks, breaks at the same moment. It works without internet, and only the timer is shared. Your tasks, notes and history stay on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Text("Your name")
                    .font(.system(size: 12, weight: .medium))
                TextField("First name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                    .disabled(group.isInGroup)
                Text("What friends see")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }

            Divider().overlay(NonnaTheme.line)

            switch group.role {
            case .none:
                notInGroup
            case .hosting:
                hosting
            case let .joining(host):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Joining \(host)'s group…")
                        .font(.system(size: 13, weight: .medium))
                }
            case let .following(host):
                following(host: host)
            }

            if let problem = group.lastProblem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(26)
        .frame(width: 500)
        .background(NonnaTheme.cream)
        .onAppear { group.startLooking() }
        .onDisappear { if group.role == .none { group.stopLooking() } }
    }

    @ViewBuilder
    private var notInGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Groups nearby")
                .font(.system(size: 13, weight: .semibold))
            if group.nearby.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for friends' groups. Ask one of them to start a group.")
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
            } else {
                ForEach(group.nearby) { nearby in
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(NonnaTheme.terracotta)
                        Text("\(nearby.hostName)'s group")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button("Join") { group.join(nearby) }
                            .buttonStyle(NonnaButtonStyle())
                    }
                    .padding(10)
                    .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("Joining replaces your timer with the group's. Anything you're timing now is saved first.")
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
        }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Or lead one")
                    .font(.system(size: 13, weight: .semibold))
                Text("Your timer becomes the group's. Start, pause and breaks happen for everyone.")
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button("Start a Group") {
                group.stopLooking()
                group.startHosting()
            }
            .buttonStyle(NonnaButtonStyle())
        }
    }

    private var hosting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("You're leading the group", systemImage: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            Text(group.members.count <= 1
                 ? "Waiting for friends to join. They open Study together on their Mac and choose your group."
                 : "With \(group.members.dropFirst().joined(separator: ", ")). Your timer is everyone's: start, pause and breaks happen for all of you.")
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("End the Group") { group.leave() }
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
    }

    private func following(host: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("In \(host)'s group", systemImage: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NonnaTheme.terracotta)
            Text("\(host) leads the timer, so blocks and breaks start for you when they do. Your blocks still save on your Mac as usual.")
                .font(.system(size: 12))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Leave the Group") { group.leave() }
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
    }
}

/// On the Focus screen while in a group: who's studying with you, and a way out.
struct StudyGroupBar: View {
    let onOpen: () -> Void
    private var group: StudyGroup { StudyGroup.shared }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(NonnaTheme.terracotta)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(NonnaTheme.secondaryInk)
            }
            Spacer()
            Button("Group…", action: onOpen)
                .buttonStyle(NonnaButtonStyle(prominent: false))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(NonnaTheme.terracotta.opacity(0.08))
                .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NonnaTheme.terracotta.opacity(0.35), lineWidth: 0.8) }
        }
    }

    private var others: [String] {
        switch group.role {
        case .hosting: Array(group.members.dropFirst())
        default: group.members
        }
    }

    private var title: String {
        switch group.role {
        case .hosting: others.isEmpty ? "Your group is open" : "Studying with \(others.joined(separator: ", "))"
        case let .following(host): "In \(host)'s group"
        case let .joining(host): "Joining \(host)'s group…"
        case .none: ""
        }
    }

    private var detail: String {
        switch group.role {
        case .hosting: others.isEmpty ? "Friends nearby can join from Study together" : "You lead the timer for everyone"
        case let .following(host): "\(host) leads the timer; yours follows"
        default: ""
        }
    }
}

/// Beside the mood flower at the top of the Focus screen: two people, in the accent colour
/// while you're in a group.
struct TogetherButton: View {
    let action: () -> Void
    @State private var hovering = false
    private var group: StudyGroup { StudyGroup.shared }

    var body: some View {
        let active = group.isInGroup
        Button(action: action) {
            Image(systemName: active ? "person.2.fill" : "person.2")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? NonnaTheme.terracotta : NonnaTheme.secondaryInk.opacity(hovering ? 1 : 0.75))
                .frame(width: 40, height: 40)
                .background(NonnaTheme.pane(NonnaTheme.raisedPaper, hovering ? 1 : 0.7), in: Circle())
                .overlay { Circle().stroke(active ? NonnaTheme.terracotta.opacity(0.5) : NonnaTheme.line, lineWidth: 0.8) }
                .scaleEffect(hovering ? 1.05 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(NonnaMotion.quick, value: hovering)
        .help(active ? "Your study group" : "Study together with friends nearby, timers in step")
        .accessibilityLabel("Study together")
    }
}
