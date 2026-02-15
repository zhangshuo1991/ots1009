import Observation
import SwiftUI

struct AgentGridView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("代理执行面板")
                .font(.headline)

            Text("先配置每个代理命令模板，再点击任务“开始”。运行后可在下方统一日志查看实时输出。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Circle()
                                .fill(agent.tintColor)
                                .frame(width: 10, height: 10)
                            Text(agent.displayName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            if let session = task.sessions.last(where: { $0.agent == agent }) {
                                Text(session.state.displayTitle)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(session.state.tintColor.opacity(0.18), in: Capsule())
                            } else {
                                Text("未启动")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        TextField(
                            "命令模板",
                            text: Binding(
                                get: { viewModel.commandTemplates[agent] ?? agent.defaultCommand },
                                set: { viewModel.updateCommandTemplate(agent: agent, command: $0) }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(2...4)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .textFieldStyle(.roundedBorder)

                        if let session = task.sessions.last(where: { $0.agent == agent }) {
                            Text(session.latestMessage.isEmpty ? "暂无输出" : session.latestMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("估算: \(session.estimatedTokens) tokens · $\(session.estimatedCost.formatted(.number.precision(.fractionLength(3))))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }
}
