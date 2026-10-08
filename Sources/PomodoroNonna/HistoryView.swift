import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var exportMessage: String?

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

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                SectionHeading(
                    eyebrow: "Your work, remembered",
                    title: "History",
                    subtitle: "Search intentions and notes, or take your data with you."
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
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(grouped, id: \.0) { day, sessions in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                                        .font(.system(size: 13, weight: .bold, design: .default))
                                    Spacer()
                                    Text(sessions.reduce(0) { $0 + $1.focusedSeconds }.focusDurationString)
                                        .font(.system(size: 11, weight: .semibold, design: .default))
                                        .foregroundStyle(NonnaTheme.secondaryInk)
                                }
                                ForEach(sessions) { session in
                                    SessionRow(session: session)
                                        .contextMenu {
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
        .alert("Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        NonnaCard(padding: 16) {
            HStack(spacing: 15) {
                VStack(spacing: 3) {
                    Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .bold, design: .default))
                    Text(session.focusedSeconds.focusDurationString)
                        .font(.system(size: 10, design: .default))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                .frame(width: 68)

                Rectangle()
                    .fill(NonnaTheme.terracotta.opacity(0.65))
                    .frame(width: 3, height: 46)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 5) {
                    Text(session.intention.isEmpty ? session.taskName : session.intention)
                        .font(.system(size: 14, weight: .semibold, design: .default))
                    HStack(spacing: 7) {
                        Text(session.taskName)
                        Text("•")
                        Text(session.outcome.title)
                        if session.pausedSeconds > 0 {
                            Text("•")
                            Text("\(session.pausedSeconds / 60)m paused")
                        }
                    }
                    .font(.system(size: 10, design: .default))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    if !session.note.isEmpty {
                        Text(session.note)
                            .lineLimit(1)
                            .font(.system(size: 11, design: .default))
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    if let attachments = session.attachments, !attachments.isEmpty {
                        SessionAttachmentStrip(attachments: attachments)
                    }
                }
                Spacer()
                if let rating = session.focusRating {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Circle()
                                .fill(index < rating ? NonnaTheme.terracotta : NonnaTheme.line)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .help("Focus rating: \(rating) of 5")
                }
            }
        }
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
                            .font(.system(size: 8, design: .default))
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
