import Foundation
import Testing
@testable import AgentOS

struct DeliveryReportTests {
    @MainActor
    @Test
    func exportDeliveryReportWritesMarkdownAndJSON() throws {
        let viewModel = DashboardViewModel(persistence: makePersistence())
        let taskID = try #require(viewModel.selectedTaskID)

        viewModel.setValidation(taskID: taskID, testsPassed: true, lintPassed: true, reviewPassed: true, acceptancePassed: true)
        viewModel.generateSummary(taskID: taskID)

        let output = viewModel.exportDeliveryReport(taskID: taskID)
        #expect(output != nil)
        guard let output else { return }

        #expect(FileManager.default.fileExists(atPath: output.markdownURL.path))
        #expect(FileManager.default.fileExists(atPath: output.jsonURL.path))

        let markdown = try String(contentsOf: output.markdownURL, encoding: .utf8)
        #expect(markdown.contains("AgentOS 交付报告"))

        let json = try Data(contentsOf: output.jsonURL)
        let decoded = try JSONDecoder().decode(DeliveryReport.self, from: json)
        #expect(decoded.taskID == taskID)
    }

    private func makePersistence() -> SessionPersistence {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return SessionPersistence(fileURL: root.appendingPathComponent("snapshot.json"))
    }
}
