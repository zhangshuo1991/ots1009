import Observation
import SwiftUI

struct TaskSidebarView: View {
    @Bindable var viewModel: DashboardViewModel
    @State private var showingProjectSheet = false
    @State private var projectName = ""
    @State private var projectRepo = ""

    var body: some View {
        List(selection: $viewModel.selectedTaskID) {
            Section {
                projectPicker
            }

            Section("任务") {
                ForEach(viewModel.visibleTasks) { task in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(task.title)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Circle()
                                .fill(task.lane.tintColor)
                                .frame(width: 8, height: 8)
                        }

                        HStack {
                            Text(task.lane.title)
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(task.lane.tintColor.opacity(0.16), in: Capsule())
                            Text(task.status.displayTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(task.sessions.count) 会话")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(task.id)
                    .contextMenu {
                        Button("复制任务", systemImage: "doc.on.doc") {
                            viewModel.duplicateTask(task.id)
                        }
                        Button("删除任务", systemImage: "trash", role: .destructive) {
                            viewModel.deleteTask(task.id)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomActions
        }
        .sheet(isPresented: $showingProjectSheet) {
            NavigationStack {
                Form {
                    TextField("项目名称", text: $projectName)
                    TextField("仓库路径", text: $projectRepo)
                }
                .navigationTitle("新建项目")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showingProjectSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("创建") {
                            viewModel.createProject(name: projectName, repositoryPath: projectRepo)
                            projectName = ""
                            projectRepo = ""
                            showingProjectSheet = false
                        }
                    }
                }
            }
            .frame(minWidth: 420, minHeight: 220)
        }
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("项目", selection: Binding(
                get: { viewModel.selectedProjectID },
                set: { viewModel.selectProject($0) }
            )) {
                ForEach(viewModel.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: 8) {
                Button {
                    showingProjectSheet = true
                } label: {
                    Label("新建项目", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.createTask()
                    }
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }

    private var bottomActions: some View {
        VStack(spacing: 8) {
            if let selectedTaskID = viewModel.selectedTaskID {
                HStack(spacing: 8) {
                    Button("开始") {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.startTask(selectedTaskID)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("暂停") {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.pauseTask(selectedTaskID)
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("继续") {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.resumeTask(selectedTaskID)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
