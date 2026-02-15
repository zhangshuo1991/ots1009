import Observation
import SwiftUI

struct RecoveryPanelView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    private var failedSessions: [AgentSession] {
        task.sessions.filter { $0.state == .failed || $0.state == .cancelled || $0.state == .blocked }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("恢复中心")
                .font(.headline)

            if !failedSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("失败分类与推荐动作")
                        .font(.subheadline.weight(.semibold))

                    ForEach(failedSessions) { session in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(session.agent.tintColor)
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(session.agent.displayName) · \(session.failureCategory?.title ?? "未分类")")
                                    .font(.caption.weight(.semibold))
                                Text("建议动作：\(session.recommendedRecovery?.title ?? RecoveryAction.manualInspection.title)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if session.recommendedRecovery == .retry {
                                Button("按建议重试") {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        viewModel.retrySession(taskID: task.id, sessionID: session.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if task.recoveryPoints.isEmpty {
                Label("暂无恢复点", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(task.recoveryPoints.reversed().prefix(8))) { point in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(point.note)
                                    .font(.caption.weight(.semibold))
                                Text(point.createdAt.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("恢复到此处") {
                                withAnimation(.snappy(duration: 0.22)) {
                                    viewModel.restoreTask(taskID: task.id, recoveryPointID: point.id)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .cardSurface()
    }
}
