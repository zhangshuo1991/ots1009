import Observation
import SwiftUI

struct TaskSidebarView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("任务列表")
                    .font(.title3.bold())
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        viewModel.createTask()
                    }
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            List(selection: $viewModel.selectedTaskID) {
                ForEach(viewModel.tasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(task.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Circle()
                                .fill(task.status.tintColor)
                                .frame(width: 8, height: 8)
                        }

                        Text(task.phase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Text(task.status.displayTitle)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(task.status.tintColor.opacity(0.18), in: Capsule())

                            Spacer()

                            Text("\(task.sessions.count) 会话")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(task.id)
                    .contextMenu {
                        Button("复制任务", systemImage: "doc.on.doc") {
                            viewModel.duplicateTask(task.id)
                        }
                        Button("删除任务", systemImage: "trash", role: .destructive) {
                            viewModel.deleteTask(task.id)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("任务 \(task.title)，状态 \(task.status.displayTitle)")
                }
            }
            .listStyle(.sidebar)

            if let selectedTaskID = viewModel.selectedTaskID {
                HStack(spacing: 8) {
                    Button("开始") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.startTask(selectedTaskID)
                        }
                    }
                        .buttonStyle(.borderedProminent)
                    Button("暂停") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.pauseTask(selectedTaskID)
                        }
                    }
                        .buttonStyle(.bordered)
                    Button("继续") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.resumeTask(selectedTaskID)
                        }
                    }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .background(Color(red: 0.96, green: 0.97, blue: 0.98))
    }
}
