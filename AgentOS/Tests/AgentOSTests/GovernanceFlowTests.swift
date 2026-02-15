import Foundation
import Testing
@testable import AgentOS

struct GovernanceFlowTests {
    @MainActor
    @Test
    func approvalRequiresQuorumBeforeResume() throws {
        let viewModel = DashboardViewModel(persistence: makePersistence())
        let taskID = try #require(viewModel.selectedTaskID)
        guard let index = viewModel.tasks.firstIndex(where: { $0.id == taskID }) else {
            Issue.record("未找到任务索引")
            return
        }

        let waitingSession = AgentSession(
            agent: .codex,
            command: "echo approve",
            state: .waitingApproval,
            latestMessage: "waiting approval"
        )
        viewModel.tasks[index].sessions = [waitingSession]
        viewModel.tasks[index].status = .needsDecision
        viewModel.tasks[index].approval.requiredApprovals = 2
        viewModel.tasks[index].approval.fallbackAction = .autoBlock
        viewModel.tasks[index].approval.timeoutAt = Date().addingTimeInterval(60)

        viewModel.resolveApproval(taskID: taskID, sessionID: waitingSession.id, approve: true, role: .owner)
        #expect(viewModel.tasks[index].status == .needsDecision)
        #expect(viewModel.tasks[index].sessions.first?.state == .waitingApproval)

        viewModel.resolveApproval(taskID: taskID, sessionID: waitingSession.id, approve: true, role: .approver)
        #expect(viewModel.tasks[index].status == .inProgress)
        #expect(viewModel.tasks[index].sessions.first?.state == .running)
    }

    @MainActor
    @Test
    func timeoutFallbackBlocksWaitingSessions() throws {
        let viewModel = DashboardViewModel(persistence: makePersistence())
        let taskID = try #require(viewModel.selectedTaskID)
        guard let index = viewModel.tasks.firstIndex(where: { $0.id == taskID }) else {
            Issue.record("未找到任务索引")
            return
        }

        let waitingSession = AgentSession(
            agent: .claudeCode,
            command: "echo waiting",
            state: .waitingApproval,
            latestMessage: "waiting approval"
        )
        viewModel.tasks[index].sessions = [waitingSession]
        viewModel.tasks[index].status = .needsDecision
        viewModel.tasks[index].approval.requiredApprovals = 1
        viewModel.tasks[index].approval.fallbackAction = .autoBlock
        viewModel.tasks[index].approval.timeoutAt = Date().addingTimeInterval(-1)

        viewModel.evaluateApprovalTimeout(taskID: taskID)
        #expect(viewModel.tasks[index].sessions.first?.state == .blocked)
        #expect(viewModel.tasks[index].status == .needsDecision)
    }

    private func makePersistence() -> SessionPersistence {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return SessionPersistence(fileURL: root.appendingPathComponent("snapshot.json"))
    }
}

