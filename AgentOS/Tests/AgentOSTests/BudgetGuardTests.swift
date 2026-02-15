import Testing
@testable import AgentOS

struct BudgetGuardTests {
    @Test
    func warningsAppearNearThresholdAndApprovalBlock() {
        var task = WorkTask(
            title: "预算任务",
            goal: "验证预算预警",
            constraints: [],
            acceptanceCriteria: [],
            riskNotes: []
        )

        task.budget.tokenUsed = 100_000
        task.budget.tokenLimit = 120_000
        task.budget.costUsed = 35
        task.budget.costLimit = 40
        task.budget.runtimeSeconds = 3_100
        task.budget.runtimeLimitSeconds = 3_600
        task.sessions = [
            AgentSession(agent: .claudeCode, command: "echo waiting", state: .waitingApproval)
        ]

        let warnings = BudgetGuard().warnings(for: task)

        #expect(warnings.count >= 3)
        #expect(warnings.contains(where: { $0.contains("Token") }))
        #expect(warnings.contains(where: { $0.contains("成本") }))
        #expect(warnings.contains(where: { $0.contains("授权") }))
    }
}
