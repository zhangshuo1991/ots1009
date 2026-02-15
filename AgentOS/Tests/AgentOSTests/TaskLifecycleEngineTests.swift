import Testing
@testable import AgentOS

struct TaskLifecycleEngineTests {
    @Test
    func phaseAdvanceRespectsGates() {
        var task = WorkTask(
            title: "测试任务",
            goal: "可推进",
            constraints: [],
            acceptanceCriteria: [],
            riskNotes: []
        )

        let engine = TaskLifecycleEngine()

        #expect(engine.advance(&task))
        #expect(task.phase == .implement)

        #expect(!engine.advance(&task))

        task.sessions = [
            AgentSession(agent: .codex, command: "echo ok", state: .completed)
        ]
        #expect(engine.advance(&task))
        #expect(task.phase == .selfCheck)

        task.validation.testsPassed = true
        task.validation.lintPassed = true
        #expect(engine.advance(&task))
        #expect(task.phase == .review)

        task.validation.reviewPassed = true
        #expect(engine.advance(&task))
        #expect(task.phase == .accept)

        task.validation.acceptancePassed = true
        #expect(engine.advance(&task))
        #expect(task.status == .completed)
    }
}
