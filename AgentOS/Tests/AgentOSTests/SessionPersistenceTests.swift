import Foundation
import Testing
@testable import AgentOS

struct SessionPersistenceTests {
    @Test
    func snapshotRoundTrip() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("snapshot.json")

        let persistence = SessionPersistence(fileURL: fileURL)

        let task = WorkTask(
            title: "恢复任务",
            goal: "验证快照读写",
            constraints: ["A"],
            acceptanceCriteria: ["B"],
            riskNotes: ["C"]
        )

        let snapshot = WorkspaceSnapshot(
            tasks: [task],
            strategyProfiles: StrategyProfile.presets,
            selectedStrategyID: StrategyProfile.presets.first?.id,
            commandTemplates: ["codex": "echo codex"],
            executionMode: .localShell,
            updatedAt: Date()
        )

        try persistence.save(snapshot)
        let loaded = try persistence.load()

        #expect(loaded != nil)
        #expect(loaded?.tasks.first?.title == "恢复任务")
        #expect(loaded?.commandTemplates["codex"] == "echo codex")
    }
}
