import SwiftUI

struct TasksView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewTask = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    SectionHeading(
                        eyebrow: "Where the hours go",
                        title: "Tasks",
                        subtitle: "Lifetime totals survive renaming and archiving."
                    )
                    Spacer()
                    Button {
                        showingNewTask = true
                    } label: {
                        Label("New task", systemImage: "plus")
                    }
                    .buttonStyle(NonnaButtonStyle())
                }

                if model.tasks.isEmpty {
                    NonnaCard {
                        EmptyState(
                            icon: "checklist",
                            title: "Create your first task",
                            message: "Tasks turn individual sessions into useful lifetime totals."
                        )
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                        ForEach(model.tasks) { task in
                            TaskCard(task: task, total: model.analytics.taskTotals.first { $0.taskID == task.id })
                        }
                    }
                }
            }
            .padding(30)
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
                .environment(model)
        }
    }
}

private struct TaskCard: View {
    @Environment(AppModel.self) private var model
    let task: FocusTask
    let total: TaskTotal?

    var body: some View {
        NonnaCard(padding: 19) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    Circle()
                        .fill(NonnaTheme.taskColor(for: task.colorHex))
                        .frame(width: 13, height: 13)
                        .padding(.top, 3)
                    Text(task.name)
                        .font(.system(size: 17, weight: .bold, design: .default))
                    Spacer()
                    Menu {
                        Button("Focus on this task") {
                            model.selectedTaskID = task.id
                        }
                        Button("Archive task", role: .destructive) {
                            model.archiveTask(task.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                HStack(spacing: 22) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text((total?.seconds ?? 0).focusDurationString)
                            .font(.system(size: 23, weight: .bold, design: .default))
                            .monospacedDigit()
                        Text("TOTAL FOCUS")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .tracking(1)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(total?.sessionCount ?? 0)")
                            .font(.system(size: 23, weight: .bold, design: .default))
                            .monospacedDigit()
                        Text("SESSIONS")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .tracking(1)
                            .foregroundStyle(NonnaTheme.secondaryInk)
                    }
                }

                Button {
                    model.selectedTaskID = task.id
                    model.selectPhase(.focus)
                    if model.status == .idle { model.start() }
                } label: {
                    Label("Start focusing", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NonnaButtonStyle(color: NonnaTheme.taskColor(for: task.colorHex)))
                .disabled(model.status != .idle)
            }
        }
    }
}
