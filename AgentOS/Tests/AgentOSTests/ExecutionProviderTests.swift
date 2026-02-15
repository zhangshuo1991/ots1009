import Foundation
import Testing
@testable import AgentOS

struct ExecutionProviderTests {
    @Test
    func localShellProviderEmitsStartedAndFinished() async throws {
        let recorder = ExecutionEventRecorder()
        let provider = LocalShellExecutionProvider { event in
            Task { await recorder.append(event) }
        }
        let sessionID = UUID()

        await provider.start(sessionID: sessionID, command: "echo local-provider")
        let events = try await waitForEvents(from: recorder) { snapshot in
            hasStarted(snapshot, sessionID: sessionID) && hasFinished(snapshot, sessionID: sessionID)
        }

        #expect(hasStarted(events, sessionID: sessionID))
        #expect(hasFinished(events, sessionID: sessionID))
    }

    @Test
    func scenarioProviderInjectsTimeoutFailure() async throws {
        let recorder = ExecutionEventRecorder()
        let provider = ScenarioExecutionProvider(
            config: ScenarioExecutionConfig(
                baseDelayMilliseconds: 20,
                timeoutProbability: 0,
                failureProbability: 0,
                approvalKeyword: "approve",
                timeoutKeyword: "timeout",
                permissionDeniedKeyword: "permission-denied"
            )
        ) { event in
            Task { await recorder.append(event) }
        }
        let sessionID = UUID()

        await provider.start(sessionID: sessionID, command: "timeout scenario run")
        let events = try await waitForEvents(from: recorder) { snapshot in
            hasFailed(snapshot, sessionID: sessionID)
        }

        #expect(hasStarted(events, sessionID: sessionID))
        #expect(hasFailed(events, sessionID: sessionID))
    }

    private func waitForEvents(
        from recorder: ExecutionEventRecorder,
        timeoutSeconds: TimeInterval = 2.0,
        condition: @escaping ([AgentExecutionEvent]) -> Bool
    ) async throws -> [AgentExecutionEvent] {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            let snapshot = await recorder.snapshot()
            if condition(snapshot) {
                return snapshot
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("等待执行事件超时")
        return await recorder.snapshot()
    }

    private func hasStarted(_ events: [AgentExecutionEvent], sessionID: UUID) -> Bool {
        events.contains {
            if case let .started(id) = $0 {
                return id == sessionID
            }
            return false
        }
    }

    private func hasFinished(_ events: [AgentExecutionEvent], sessionID: UUID) -> Bool {
        events.contains {
            if case let .finished(id, _) = $0 {
                return id == sessionID
            }
            return false
        }
    }

    private func hasFailed(_ events: [AgentExecutionEvent], sessionID: UUID) -> Bool {
        events.contains {
            if case let .failed(id, _) = $0 {
                return id == sessionID
            }
            return false
        }
    }
}

actor ExecutionEventRecorder {
    private var events: [AgentExecutionEvent] = []

    func append(_ event: AgentExecutionEvent) {
        events.append(event)
    }

    func snapshot() -> [AgentExecutionEvent] {
        events
    }
}

