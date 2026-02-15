import Foundation

@available(*, deprecated, message: "Use ExecutionProvider implementations instead.")
actor AgentExecutionService {
    private let provider: LocalShellExecutionProvider

    init(eventSink: @escaping @Sendable (AgentExecutionEvent) -> Void) {
        self.provider = LocalShellExecutionProvider(eventSink: eventSink)
    }

    func start(sessionID: UUID, command: String) async {
        await provider.start(sessionID: sessionID, command: command)
    }

    func stop(sessionID: UUID) async {
        await provider.stop(sessionID: sessionID)
    }

    func stopAll() async {
        await provider.stopAll()
    }
}
