import Foundation
import Testing
@testable import AgentOS

struct WorkspaceManagementTests {
    @MainActor
    @Test
    func createProjectAndTaskShouldBindProjectContext() {
        let viewModel = DashboardViewModel(persistence: makePersistence())
        viewModel.createProject(name: "RepoA", repositoryPath: "/tmp/repo-a")
        let projectID = viewModel.selectedProjectID

        viewModel.createTask()
        let task = viewModel.selectedTask

        #expect(task?.projectID == projectID)
        #expect(task?.repositoryPath == "/tmp/repo-a")
        #expect(viewModel.projects.first(where: { $0.id == projectID })?.taskIDs.contains(task?.id ?? UUID()) == true)
    }

    @MainActor
    @Test
    func laneAndCommentUpdatesPersistInTask() throws {
        let viewModel = DashboardViewModel(persistence: makePersistence())
        let taskID = try #require(viewModel.selectedTaskID)

        viewModel.setTaskLane(taskID: taskID, lane: .review)
        viewModel.addComment(taskID: taskID, author: .reviewer, content: "请先补充回归测试")

        let task = try #require(viewModel.tasks.first(where: { $0.id == taskID }))
        #expect(task.lane == .review)
        #expect(task.comments.contains(where: { $0.content.contains("回归测试") }))
    }

    private func makePersistence() -> SessionPersistence {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return SessionPersistence(fileURL: root.appendingPathComponent("snapshot.json"))
    }
}
