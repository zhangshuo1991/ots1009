import Foundation

struct ScenarioExecutionConfig: Sendable, Codable, Hashable {
    var baseDelayMilliseconds: UInt64
    var timeoutProbability: Double
    var failureProbability: Double
    var approvalKeyword: String
    var timeoutKeyword: String
    var permissionDeniedKeyword: String

    static let `default` = ScenarioExecutionConfig(
        baseDelayMilliseconds: 320,
        timeoutProbability: 0.08,
        failureProbability: 0.06,
        approvalKeyword: "approve",
        timeoutKeyword: "timeout",
        permissionDeniedKeyword: "permission-denied"
    )
}

actor ScenarioExecutionProvider: ExecutionProvider {
    private let eventSink: @Sendable (AgentExecutionEvent) -> Void
    private let config: ScenarioExecutionConfig
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    init(
        config: ScenarioExecutionConfig = .default,
        eventSink: @escaping @Sendable (AgentExecutionEvent) -> Void
    ) {
        self.config = config
        self.eventSink = eventSink
    }

    func start(sessionID: UUID, command: String) async {
        if runningTasks[sessionID] != nil {
            return
        }

        let task = Task { [config, eventSink] in
            do {
                try await Task.sleep(nanoseconds: config.baseDelayMilliseconds * 1_000_000)
                eventSink(.started(sessionID: sessionID))

                if command.localizedCaseInsensitiveContains(config.permissionDeniedKeyword) {
                    eventSink(.failed(sessionID: sessionID, message: "Permission denied in scenario mode"))
                    return
                }

                if command.localizedCaseInsensitiveContains(config.approvalKeyword) {
                    eventSink(.waitingApproval(sessionID: sessionID, line: "Scenario: waiting approval"))
                }

                if command.localizedCaseInsensitiveContains(config.timeoutKeyword) ||
                    Double.random(in: 0...1) < config.timeoutProbability
                {
                    try await Task.sleep(nanoseconds: 1_300_000_000)
                    eventSink(.failed(sessionID: sessionID, message: "Scenario timeout"))
                    return
                }

                eventSink(.output(sessionID: sessionID, line: "Scenario: planning"))
                try await Task.sleep(nanoseconds: 180_000_000)
                eventSink(.output(sessionID: sessionID, line: "Scenario: implementing"))
                try await Task.sleep(nanoseconds: 180_000_000)

                if Double.random(in: 0...1) < config.failureProbability {
                    eventSink(.failed(sessionID: sessionID, message: "Scenario injected failure"))
                    return
                }

                eventSink(.output(sessionID: sessionID, line: "Scenario: validating"))
                try await Task.sleep(nanoseconds: 140_000_000)
                eventSink(.finished(sessionID: sessionID, exitCode: 0))
            } catch {
                eventSink(.cancelled(sessionID: sessionID))
            }
        }

        runningTasks[sessionID] = task
    }

    func stop(sessionID: UUID) async {
        runningTasks[sessionID]?.cancel()
        runningTasks[sessionID] = nil
        eventSink(.cancelled(sessionID: sessionID))
    }

    func stopAll() async {
        for sessionID in runningTasks.keys {
            await stop(sessionID: sessionID)
        }
    }
}

