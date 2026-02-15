import Observation
import SwiftUI

struct TaskDetailView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    @State private var draftTitle: String = ""
    @State private var draftGoal: String = ""
    @State private var draftConstraints: String = ""
    @State private var draftAcceptance: String = ""
    @State private var draftRisks: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                PhaseTimelineView(phase: task.phase, history: task.phaseHistory)
                StrategyPanelView(viewModel: viewModel)
                metadataEditor
                validationPanel
                keyboardHintsPanel
                DecisionCenterView(viewModel: viewModel, task: task)
                AgentGridView(viewModel: viewModel, task: task)
                BudgetPanelView(task: task, warnings: viewModel.budgetWarnings(for: task.id))
                RecoveryPanelView(viewModel: viewModel, task: task)
                SummaryPanelView(viewModel: viewModel, task: task)
                LogPanelView(logText: viewModel.combinedLog(for: task.id))
            }
            .padding(.bottom, 48)
        }
        .onAppear(perform: syncDraft)
        .onChange(of: task.id) { _, _ in syncDraft() }
        .navigationTitle(task.title)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(task.goal)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(task.status.displayTitle)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(task.status.tintColor.opacity(0.2), in: Capsule())

                HStack(spacing: 8) {
                    Button("开始") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.startTask(task.id)
                        }
                    }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("r", modifiers: [.command])
                    Button("暂停") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.pauseTask(task.id)
                        }
                    }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(".", modifiers: [.command])
                    Button("继续") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.resumeTask(task.id)
                        }
                    }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("u", modifiers: [.command])
                    Button("推进阶段") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.advanceSelectedTaskPhase()
                        }
                    }
                        .buttonStyle(.bordered)
                        .keyboardShortcut("p", modifiers: [.command, .shift])
                }
                .controlSize(.small)
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
                    withAnimation(.snappy(duration: 0.22)) {
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

    private var keyboardHintsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("键盘优先路径")
                .font(.headline)
            Text("⌘R 开始执行 · ⌘. 暂停 · ⌘U 继续 · ⇧⌘P 推进阶段")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("在决策中心可直接用按钮完成审批与重试，全流程支持无鼠标推进。")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
    }
}
