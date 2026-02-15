import Observation
import SwiftUI

struct DecisionCenterView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask
    @State private var approvalRole: ApprovalRole = .owner
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var waitingApprovalSessions: [AgentSession] {
        task.sessions.filter { $0.state == .waitingApproval }
    }

    private var retryableSessions: [AgentSession] {
        task.sessions.filter { $0.state == .failed || $0.state == .blocked || $0.state == .cancelled }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("决策中心")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("审批策略")
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 12) {
                    Text("要求审批: \(task.approval.requiredApprovals)")
                    Text("已批准: \(task.approval.grantedApprovals.count)")
                    Text("超时动作: \(task.approval.fallbackAction.title)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let remaining = viewModel.approvalRemainingSeconds(taskID: task.id) {
                    Text("剩余审批时间: \(remaining)s")
                        .font(.caption2)
                        .foregroundStyle(remaining <= 10 ? .red : .secondary)
                }
            }

            Picker("审批角色", selection: $approvalRole) {
                ForEach(ApprovalRole.allCases) { role in
                    Text(role.title).tag(role)
                }
            }
            .pickerStyle(.segmented)

            if !task.validation.hasConflict && waitingApprovalSessions.isEmpty && retryableSessions.isEmpty {
                Label("当前无待处理决策", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if task.validation.hasConflict {
                VStack(alignment: .leading, spacing: 8) {
                    Label("检测到冲突，任务需人工裁决", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                    Button("标记冲突已处理，恢复推进") {
                        withAnimation(.snappy(duration: 0.22)) {
                            viewModel.resolveConflict(taskID: task.id)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if !waitingApprovalSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("待授权会话")
                        .font(.subheadline.weight(.semibold))
                    ForEach(waitingApprovalSessions) { session in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(session.agent.tintColor)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.agent.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(session.latestMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Button("授权") {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        viewModel.resolveApproval(
                                            taskID: task.id,
                                            sessionID: session.id,
                                            approve: true,
                                            role: approvalRole
                                        )
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                                Button("阻塞") {
                                    withAnimation(.snappy(duration: 0.22)) {
                                        viewModel.resolveApproval(
                                            taskID: task.id,
                                            sessionID: session.id,
                                            approve: false,
                                            role: approvalRole
                                        )
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            if !retryableSessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("可重试会话")
                        .font(.subheadline.weight(.semibold))
                    ForEach(retryableSessions) { session in
                        HStack {
                            Text(session.agent.displayName)
                                .font(.caption)
                            Spacer()
                            Text(session.state.displayTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Button("重试") {
                                withAnimation(.snappy(duration: 0.22)) {
                                    viewModel.retrySession(taskID: task.id, sessionID: session.id)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .cardSurface()
        .onReceive(timer) { _ in
            viewModel.evaluateApprovalTimeout(taskID: task.id)
        }
    }
}
