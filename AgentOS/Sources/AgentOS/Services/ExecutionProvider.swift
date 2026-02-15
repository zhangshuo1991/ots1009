import Foundation

enum AgentExecutionEvent: Sendable {
    case started(sessionID: UUID)
    case output(sessionID: UUID, line: String)
    case waitingApproval(sessionID: UUID, line: String)
    case finished(sessionID: UUID, exitCode: Int32)
    case failed(sessionID: UUID, message: String)
    case cancelled(sessionID: UUID)
}

enum ExecutionMode: String, Codable, CaseIterable {
    case localShell
    case scenario

    var title: String {
        switch self {
        case .localShell: return "本地执行"
        case .scenario: return "场景模拟"
        }
    }
}

protocol ExecutionProvider: Sendable {
    func start(sessionID: UUID, command: String) async
    func stop(sessionID: UUID) async
    func stopAll() async
}

