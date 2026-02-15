import Observation
import SwiftUI

private enum TaskDetailTab: String, CaseIterable, Identifiable {
    case workspace
    case execution
    case governance
    case collaboration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: return "工作区配置"
        case .execution: return "执行"
        case .governance: return "治理"
        case .collaboration: return "协作"
        }
    }
}

struct TaskDetailView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    @State private var selectedTab: TaskDetailTab = .workspace
    @State private var draftTitle: String = ""
    @State private var draftGoal: String = ""
    @State private var draftConstraints: String = ""
    @State private var draftAcceptance: String = ""
    @State private var draftRisks: String = ""
    @State private var draftRepositoryPath: String = ""
    @State private var draftBranchName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("视图", selection: $selectedTab) {
                ForEach(TaskDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedTab {
                    case .workspace:
                        quickStartPanel
                        StrategyPanelView(viewModel: viewModel)
                        CLIRuntimePanelView(viewModel: viewModel)
                        sourceContextEditor
                        metadataEditor
                        validationPanel
                    case .execution:
                        PhaseTimelineView(phase: task.phase, history: task.phaseHistory)
                        AgentGridView(viewModel: viewModel, task: task)
                        BudgetPanelView(task: task, warnings: viewModel.budgetWarnings(for: task.id))
                        LogPanelView(logText: viewModel.combinedLog(for: task.id))
                    case .governance:
                        DecisionCenterView(viewModel: viewModel, task: task)
                        RecoveryPanelView(viewModel: viewModel, task: task)
                        SummaryPanelView(viewModel: viewModel, task: task)
                    case .collaboration:
                        CollaborationPanelView(viewModel: viewModel, task: task)
                    }
                }
                .padding(.bottom, 72)
            }
        }
        .onAppear(perform: syncDraft)
        .onChange(of: task.id) { _, _ in syncDraft() }
        .navigationTitle(task.title)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(task.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(task.status.displayTitle)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(task.status.tintColor.opacity(0.18), in: Capsule())
                    Text(task.lane.title)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(task.lane.tintColor.opacity(0.18), in: Capsule())
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button("开始") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.startTask(task.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: [.command])

                Button("暂停") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.pauseTask(task.id)
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(".", modifiers: [.command])

                Button("继续") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.resumeTask(task.id)
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("u", modifiers: [.command])

                Button("推进阶段") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.advanceSelectedTaskPhase()
                    }
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
            .controlSize(.small)
        }
        .cardSurface()
    }

    private var quickStartPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用流程")
                .font(.headline)
            Text("1) 先在“CLI 运行时接入”确认工具已安装；2) 填写仓库路径与分支；3) 在“执行”页配置命令并点击开始；4) 在“治理/协作”页做审批、恢复与评论。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardSurface()
    }

    private var sourceContextEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("仓库与分支")
                .font(.headline)
            HStack(spacing: 10) {
                TextField("仓库路径", text: $draftRepositoryPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                TextField("分支", text: $draftBranchName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }
            HStack {
                Spacer()
                Button("保存仓库上下文") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.updateTaskSource(
                            taskID: task.id,
                            repositoryPath: draftRepositoryPath,
                            branchName: draftBranchName
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardSurface()
    }

    private var metadataEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("任务定义")
                .font(.headline)

            TextField("任务标题", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            TextField("任务目标", text: $draftGoal, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .top, spacing: 12) {
                textAreaCard(title: "约束", text: $draftConstraints)
                textAreaCard(title: "验收标准", text: $draftAcceptance)
                textAreaCard(title: "风险", text: $draftRisks)
            }

            HStack {
                Spacer()
                Button("保存定义") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.updateTaskMeta(
                            taskID: task.id,
                            title: draftTitle,
                            goal: draftGoal,
                            constraints: splitLines(draftConstraints),
                            acceptanceCriteria: splitLines(draftAcceptance),
                            riskNotes: splitLines(draftRisks)
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardSurface()
    }

    private var validationPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("阶段门验证")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                validationToggle(title: "测试通过", systemImage: "checkmark.circle", value: task.validation.testsPassed) {
                    viewModel.setValidation(taskID: task.id, testsPassed: !task.validation.testsPassed)
                }
                validationToggle(title: "Lint 通过", systemImage: "checkmark.seal", value: task.validation.lintPassed) {
                    viewModel.setValidation(taskID: task.id, lintPassed: !task.validation.lintPassed)
                }
                validationToggle(title: "评审通过", systemImage: "person.2.badge.gearshape", value: task.validation.reviewPassed) {
                    viewModel.setValidation(taskID: task.id, reviewPassed: !task.validation.reviewPassed)
                }
                validationToggle(title: "验收通过", systemImage: "checkmark.shield", value: task.validation.acceptancePassed) {
                    viewModel.setValidation(taskID: task.id, acceptancePassed: !task.validation.acceptancePassed)
                }
                validationToggle(title: "存在冲突", systemImage: "exclamationmark.triangle", value: task.validation.hasConflict) {
                    viewModel.setValidation(taskID: task.id, hasConflict: !task.validation.hasConflict)
                }
            }
        }
        .cardSurface()
    }

    private func textAreaCard(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.system(size: 12))
                .frame(minHeight: 100)
                .clipShape(.rect(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.1), lineWidth: 1)
                )
        }
    }

    private func validationToggle(
        title: String,
        systemImage: String,
        value: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(value ? Color.green.opacity(0.18) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，当前\(value ? "已通过" : "未通过")")
    }

    private func splitLines(_ text: String) -> [String] {
        text
            .split(whereSeparator: { $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func syncDraft() {
        draftTitle = task.title
        draftGoal = task.goal
        draftConstraints = task.constraints.joined(separator: "\n")
        draftAcceptance = task.acceptanceCriteria.joined(separator: "\n")
        draftRisks = task.riskNotes.joined(separator: "\n")
        draftRepositoryPath = task.repositoryPath
        draftBranchName = task.branchName
    }
}
