import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var exportMessage: String?
    @State private var editing: FocusSession?

    private var filtered: [FocusSession] {
        guard !search.isEmpty else { return model.sessions }
        return model.sessions.filter {
            $0.taskName.localizedCaseInsensitiveContains(search) ||
            $0.intention.localizedCaseInsensitiveContains(search) ||
            $0.note.localizedCaseInsensitiveContains(search) ||
            ($0.attachments ?? []).contains { $0.caption.localizedCaseInsensitiveContains(search) }
        }
    }

    private var grouped: [(Date, [FocusSession])] {
        let calendar = Calendar.current
        return Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.startedAt) }
            .sorted { $0.key > $1.key }
    }

    private var listColorsByID: [UUID: String] {
        Dictionary(model.data.tasks.map { ($0.id, $0.colorHex) }, uniquingKeysWith: { first, _ in first })
    }

    /// The list's own colour; a block whose list was removed falls back to the neutral used elsewhere.
    private func listColor(for session: FocusSession, in colors: [UUID: String]) -> Color {
        let hex = session.taskID.flatMap { colors[$0] }
            ?? model.data.tasks.first { $0.name.caseInsensitiveCompare(session.taskName) == .orderedSame }?.colorHex
            ?? "8D8379"
        return NonnaTheme.taskColor(for: hex)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                SectionHeading(
                    title: "History",
                    subtitle: "Click a session to fix its name or list. Search, or take your data with you."
                )
                Spacer()
                TextField("Search history", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button {
                    do {
                        let url = try model.exportCSV()
                        exportMessage = "Exported to \(url.lastPathComponent)"
                    } catch CocoaError.userCancelled {
                        // The user closed the save panel.
                    } catch {
                        exportMessage = error.localizedDescription
                    }
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NonnaButtonStyle(prominent: false))
            }
            .padding(30)

            if grouped.isEmpty {
                Spacer()
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: search.isEmpty ? "Nothing here yet" : "No matching sessions",
                    message: search.isEmpty ? "Finish your first focus session and its story will appear here." : "Try a different task, intention, or note."
                )
                Spacer()
            } else {
                let listColors = listColorsByID
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        HistoryColumnHeader()
                        ForEach(grouped, id: \.0) { day, sessions in
                            VStack(alignment: .leading, spacing: 0) {
                                DayHeaderStrip(day: day, seconds: sessions.reduce(0) { $0 + $1.focusedSeconds })
                                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                    if index > 0 {
                                        Rectangle()
                                            .fill(NonnaTheme.line.opacity(0.6))
                                            .frame(height: 1)
                                            .padding(.horizontal, HistoryTable.inset)
                                            .accessibilityHidden(true)
                                    }
                                    SessionRow(session: session, listColor: listColor(for: session, in: listColors)) { editing = session }
                                        .contextMenu {
                                            Button("Edit session…") { editing = session }
                                            Button("Delete session", role: .destructive) {
                                                if let index = model.sessions.firstIndex(where: { $0.id == session.id }) {
                                                    model.deleteSessions(at: IndexSet(integer: index))
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(item: $editing) { session in
            EditSessionSheet(session: session) { editing = nil }
        }
        .alert("Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}

/// Shared column geometry, so the column header, day strips and rows line up.
private enum HistoryTable {
    static let inset: CGFloat = 12
    static let gap: CGFloat = 14
    static let lineHeight: CGFloat = 18
    static let time: CGFloat = 64
    static let pencil: CGFloat = 14
    static let duration: CGFloat = 72
    static let rating: CGFloat = 44
}

private struct HistoryColumnHeader: View {
    var body: some View {
        HStack(spacing: HistoryTable.gap) {
            Text("Time").frame(width: HistoryTable.time, alignment: .leading)
            Text("Session").frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: HistoryTable.pencil, height: 1)
            Text("Duration").frame(width: HistoryTable.duration, alignment: .trailing)
            Text("Focus").frame(width: HistoryTable.rating, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(NonnaTheme.secondaryInk)
        .padding(.horizontal, HistoryTable.inset)
        .padding(.bottom, -8)
        .accessibilityHidden(true)
    }
}

/// The muted band that opens each day: the date on the left, its focused total on the right.
private struct DayHeaderStrip: View {
    let day: Date
    let seconds: Int

    var body: some View {
        HStack {
            Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .foregroundStyle(NonnaTheme.ink)
            Spacer()
            Text(seconds.focusDurationString)
                .monospacedDigit()
                .foregroundStyle(NonnaTheme.secondaryInk)
        }
        .font(.system(size: 12))
        .padding(.horizontal, HistoryTable.inset)
        .frame(height: 30)
        .background(NonnaTheme.ink.opacity(NonnaTheme.isDark ? 0.05 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SessionRow: View {
    let session: FocusSession
    let listColor: Color
    let onEdit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var title: String { session.intention.isEmpty ? listName : session.intention }
    private var listName: String { session.taskName.isEmpty ? "Uncategorized" : session.taskName }
    private var time: String { session.startedAt.formatted(date: .omitted, time: .shortened) }
    private var accessibilityText: String {
        var parts = [time, title, listName, session.focusedSeconds.focusDurationString]
        if session.outcome != .completed { parts.append(session.outcome.title) }
        if let rating = session.focusRating { parts.append("Focus rating \(rating) of 5") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onEdit) { row }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : NonnaMotion.quick, value: hovering)
            .help("Edit this session")
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Edit this session")
    }

    private var row: some View {
        HStack(alignment: .top, spacing: HistoryTable.gap) {
            Text(time)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NonnaTheme.secondaryInk)
                .frame(width: HistoryTable.time, height: HistoryTable.lineHeight, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(NonnaTheme.ink)
                    .lineLimit(1)
                    .frame(height: HistoryTable.lineHeight)
                HStack(spacing: 10) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(listColor)
                            .frame(width: 7, height: 7)
                        Text(listName)
                    }
                    if session.outcome != .completed {
                        Text(session.outcome.title)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .frame(height: 16)
                            .background(NonnaTheme.ink.opacity(0.06), in: Capsule())
                    }
                    if session.pausedSeconds > 0 {
                        Text("\(session.pausedSeconds / 60)m paused")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .lineLimit(1)
                if !session.note.isEmpty {
                    Text(session.note)
                        .lineLimit(1)
                        .font(.system(size: 11))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                if let attachments = session.attachments, !attachments.isEmpty {
                    SessionAttachmentStrip(attachments: attachments)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                .opacity(hovering ? 1 : 0)
                .frame(width: HistoryTable.pencil, height: HistoryTable.lineHeight)
                .accessibilityHidden(true)

            Text(session.focusedSeconds.focusDurationString)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NonnaTheme.ink)
                .frame(width: HistoryTable.duration, height: HistoryTable.lineHeight, alignment: .trailing)

            Group {
                if let rating = session.focusRating {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(index < rating ? NonnaTheme.terracotta : NonnaTheme.strongLine)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .help("Focus rating: \(rating) of 5")
                    .accessibilityLabel("Focus rating: \(rating) of 5")
                } else {
                    Color.clear
                }
            }
            .frame(width: HistoryTable.rating, height: HistoryTable.lineHeight, alignment: .trailing)
        }
        .padding(.horizontal, HistoryTable.inset)
        .padding(.vertical, 11)
        .background(NonnaTheme.ink.opacity(hovering ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct SessionAttachmentStrip: View {
    let attachments: [SessionImageAttachment]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(attachments.prefix(3))) { attachment in
                VStack(alignment: .leading, spacing: 3) {
                    StoredAttachmentImage(fileName: attachment.fileName)
                        .frame(width: 72, height: 48)
                        .background(NonnaTheme.cream)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    if !attachment.caption.isEmpty {
                        Text(attachment.caption)
                            .font(.system(size: 10, design: .default))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                            .lineLimit(1)
                            .frame(width: 72, alignment: .leading)
                    }
                }
            }
            if attachments.count > 3 {
                Text("+\(attachments.count - 3)")
                    .font(.system(size: 10, weight: .semibold, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .frame(width: 36, height: 48)
                    .background(NonnaTheme.raisedPaper)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(.top, 3)
    }
}
