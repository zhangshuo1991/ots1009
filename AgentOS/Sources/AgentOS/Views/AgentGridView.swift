import Observation
import SwiftUI

struct AgentGridView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("多代理协同面板")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
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

                        TextEditor(
                            text: Binding(
                                get: { viewModel.commandTemplates[agent] ?? agent.defaultCommand },
                                set: { viewModel.updateCommandTemplate(agent: agent, command: $0) }
                            )
                        )
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(height: 96)
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )

                        if let session = task.sessions.last(where: { $0.agent == agent }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("最新输出")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(session.latestMessage.isEmpty ? "--" : session.latestMessage)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(
                                    "估算: \(session.estimatedTokens) tokens · $\(session.estimatedCost.formatted(.number.precision(.fractionLength(3))))"
                                )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }
}
