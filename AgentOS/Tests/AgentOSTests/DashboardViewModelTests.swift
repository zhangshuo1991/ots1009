import Foundation
import Testing
@testable import AgentOS

struct DashboardViewModelTests {
    @MainActor
    @Test
    func resumeTaskRelaunchesSessions() throws {
        let persistence = makePersistence()
        let viewModel = DashboardViewModel(persistence: persistence)
        let taskID = try #require(viewModel.selectedTaskID)

        for agent in AgentKind.allCases {
            viewModel.updateCommandTemplate(agent: agent, command: "sleep 5")
        }

        viewModel.startTask(taskID)
        let startedSessionCount = viewModel.selectedTask?.sessions.count ?? 0
        #expect(startedSessionCount > 0)

        viewModel.pauseTask(taskID)
        #expect(viewModel.selectedTask?.status == .paused)
        let pausedSessionCount = viewModel.selectedTask?.sessions.count ?? 0

        viewModel.resumeTask(taskID)

        #expect(viewModel.selectedTask?.status == .inProgress)
        #expect((viewModel.selectedTask?.sessions.count ?? 0) > pausedSessionCount)

        viewModel.pauseTask(taskID)
    }

    @MainActor
    @Test
    func autoAdvancePipelineMovesAcrossValidationGates() async throws {
        let persistence = makePersistence()
        let viewModel = DashboardViewModel(persistence: persistence)
        let taskID = try #require(viewModel.selectedTaskID)

        for agent in AgentKind.allCases {
            viewModel.updateCommandTemplate(agent: agent, command: "echo done")
        }

        viewModel.startTask(taskID)
        #expect(viewModel.selectedTask?.phase == .implement)

        try await waitForPhase(.selfCheck, taskID: taskID, in: viewModel)
        #expect(viewModel.selectedTask?.phase == .selfCheck)

        viewModel.setValidation(taskID: taskID, testsPassed: true, lintPassed: true)
        #expect(viewModel.selectedTask?.phase == .review)

        viewModel.setValidation(taskID: taskID, reviewPassed: true)
        #expect(viewModel.selectedTask?.phase == .accept)

        viewModel.setValidation(taskID: taskID, acceptancePassed: true)
        #expect(viewModel.selectedTask?.status == .completed)
    }

    @MainActor
    @Test
    func resolveApprovalAndRetrySession() throws {
        let persistence = makePersistence()
        let viewModel = DashboardViewModel(persistence: persistence)
        let taskID = try #require(viewModel.selectedTaskID)
        guard let index = viewModel.tasks.firstIndex(where: { $0.id == taskID }) else {
            Issue.record("找不到任务索引")
            return
        }

        let waitingSession = AgentSession(
            agent: .codex,
            command: "echo approve request",
            state: .waitingApproval,
            latestMessage: "need approve"
        )
        viewModel.tasks[index].sessions = [waitingSession]
        viewModel.tasks[index].status = .needsDecision

        viewModel.resolveApproval(taskID: taskID, sessionID: waitingSession.id, approve: false)
        #expect(viewModel.tasks[index].sessions.first?.state == .blocked)
        #expect(viewModel.tasks[index].status == .needsDecision)

        viewModel.retrySession(taskID: taskID, sessionID: waitingSession.id)
        #expect(viewModel.tasks[index].sessions.count == 2)
        #expect(viewModel.tasks[index].sessions.last?.state == .running)
    }

    @MainActor
    @Test
    func restoreTaskUsesRecoveryCheckpoint() throws {
        let persistence = makePersistence()
        let viewModel = DashboardViewModel(persistence: persistence)
        let taskID = try #require(viewModel.selectedTaskID)

        for agent in AgentKind.allCases {
            viewModel.updateCommandTemplate(agent: agent, command: "sleep 5")
        }

        viewModel.startTask(taskID)
        viewModel.pauseTask(taskID)

        guard let pausedPoint = viewModel.selectedTask?.recoveryPoints.last(where: { $0.note.contains("手动暂停任务") }) else {
            Issue.record("未找到暂停恢复点")
            return
        }

        viewModel.resumeTask(taskID)
        #expect(viewModel.selectedTask?.status == .inProgress)

        viewModel.restoreTask(taskID: taskID, recoveryPointID: pausedPoint.id)
        #expect(viewModel.selectedTask?.status == .paused)
        #expect(viewModel.selectedTask?.phase == .implement)
    }

    @MainActor
    @Test
    func generateSummaryProducesStructuredOutput() throws {
        let persistence = makePersistence()
        let viewModel = DashboardViewModel(persistence: persistence)
        let taskID = try #require(viewModel.selectedTaskID)
        guard let index = viewModel.tasks.firstIndex(where: { $0.id == taskID }) else {
            Issue.record("找不到任务索引")
            return
        }

        viewModel.tasks[index].sessions = [
            AgentSession(agent: .codex, command: "echo done", state: .completed),
            AgentSession(agent: .claudeCode, command: "echo failed", state: .failed),
            AgentSession(agent: .geminiCLI, command: "echo wait", state: .waitingApproval),
        ]
        viewModel.tasks[index].status = .needsDecision
        viewModel.tasks[index].phase = .review
        viewModel.tasks[index].budget.tokenUsed = 90_000
        viewModel.tasks[index].budget.costUsed = 20

        viewModel.generateSummary(taskID: taskID)
        let summary = viewModel.tasks[index].summary
        #expect(!summary.isEmpty)
        #expect(summary.contains("会话统计"))
        #expect(summary.contains("下一步"))
        #expect(summary.contains("风险告警"))
    }

    @MainActor
    private func waitForPhase(_ phase: TaskPhase, taskID: UUID, in viewModel: DashboardViewModel) async throws {
        let maxAttempts = 60
        for _ in 0..<maxAttempts {
            if viewModel.tasks.first(where: { $0.id == taskID })?.phase == phase {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        Issue.record("等待阶段 \(phase.title) 超时")
    }

    private func makePersistence() -> SessionPersistence {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return SessionPersistence(fileURL: root.appendingPathComponent("snapshot.json"))
    }
}
