import Foundation

actor LocalShellExecutionProvider: ExecutionProvider {
    private let eventSink: @Sendable (AgentExecutionEvent) -> Void
    private var processes: [UUID: Process] = [:]
    private var outputTasks: [UUID: Task<Void, Never>] = [:]

    init(eventSink: @escaping @Sendable (AgentExecutionEvent) -> Void) {
        self.eventSink = eventSink
    }

    func start(sessionID: UUID, command: String) async {
        if processes[sessionID] != nil {
            return
        }

        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        process.terminationHandler = { [eventSink] process in
            eventSink(.finished(sessionID: sessionID, exitCode: process.terminationStatus))
        }

        do {
            try process.run()
            processes[sessionID] = process
            eventSink(.started(sessionID: sessionID))

            outputTasks[sessionID] = Task {
                do {
                    for try await line in outputPipe.fileHandleForReading.bytes.lines {
                        if line.localizedCaseInsensitiveContains("approve") ||
                            line.localizedCaseInsensitiveContains("authorization")
                        {
                            eventSink(.waitingApproval(sessionID: sessionID, line: line))
                        } else {
                            eventSink(.output(sessionID: sessionID, line: line))
                        }
                    }
                } catch {
                    eventSink(.failed(sessionID: sessionID, message: error.localizedDescription))
                }
            }
        } catch {
            eventSink(.failed(sessionID: sessionID, message: error.localizedDescription))
        }
    }

    func stop(sessionID: UUID) async {
        if let process = processes[sessionID] {
            process.terminate()
            processes[sessionID] = nil
        }

        outputTasks[sessionID]?.cancel()
        outputTasks[sessionID] = nil
        eventSink(.cancelled(sessionID: sessionID))
    }

    func stopAll() async {
        for sessionID in processes.keys {
            await stop(sessionID: sessionID)
        }
    }
}

