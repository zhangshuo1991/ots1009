import Foundation

struct CodexConversationBootstrapResult: Sendable {
    let conversationID: String
    let rolloutPath: String?
}

protocol CodexConversationBootstrapping: AnyObject {
    func createConversation(
        workingDirectory: String,
        environment: [String: String],
        timeout: TimeInterval
    ) throws -> CodexConversationBootstrapResult
}

enum CodexConversationBootstrapError: LocalizedError {
    case launchFailed(String)
    case protocolTimedOut(String)
    case protocolError(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return "Codex 会话预创建失败：\(message)"
        case .protocolTimedOut(let stage):
            return "Codex 协议超时（\(stage)）"
        case .protocolError(let message):
            return "Codex 协议错误：\(message)"
        case .invalidResponse(let message):
            return "Codex 协议返回无效：\(message)"
        }
    }
}

final class CodexConversationBootstrapper: CodexConversationBootstrapping {
    private enum RequestID {
        static let initialize = 1
        static let newConversation = 2
    }

    private final class BootstrapState: @unchecked Sendable {
        let lock = NSLock()
        var stdoutBuffer = Data()
        var stderrBuffer = Data()
        var stderrLines: [String] = []
        var initializeError: String?
        var bootstrapError: String?
        var result: CodexConversationBootstrapResult?
    }

    func createConversation(
        workingDirectory: String,
        environment: [String: String],
        timeout: TimeInterval = 8.0
    ) throws -> CodexConversationBootstrapResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let state = BootstrapState()
        let initializeSemaphore = DispatchSemaphore(value: 0)
        let conversationSemaphore = DispatchSemaphore(value: 0)

        let handleStdoutLine: @Sendable (String) -> Void = { rawLine in
            guard let data = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let payload = object as? [String: Any],
                  let idRaw = payload["id"],
                  let requestID = Self.parseRequestID(idRaw)
            else {
                return
            }

            if let error = payload["error"] as? [String: Any],
               let errorMessage = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorMessage.isEmpty {
                state.lock.withLock {
                    if requestID == RequestID.initialize {
                        state.initializeError = errorMessage
                    }
                    if requestID == RequestID.newConversation {
                        state.bootstrapError = errorMessage
                    }
                }
                if requestID == RequestID.initialize {
                    initializeSemaphore.signal()
                }
                if requestID == RequestID.newConversation {
                    conversationSemaphore.signal()
                }
                return
            }

            if requestID == RequestID.initialize {
                initializeSemaphore.signal()
                return
            }

            if requestID == RequestID.newConversation {
                guard let response = payload["result"] as? [String: Any] else {
                    state.lock.withLock {
                        state.bootstrapError = "newConversation 缺少 result"
                    }
                    conversationSemaphore.signal()
                    return
                }
                guard let conversationID = response["conversationId"] as? String,
                      !conversationID.isEmpty
                else {
                    state.lock.withLock {
                        state.bootstrapError = "newConversation 返回缺少 conversationId"
                    }
                    conversationSemaphore.signal()
                    return
                }

                let rolloutPath = (response["rolloutPath"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                state.lock.withLock {
                    state.result = CodexConversationBootstrapResult(
                        conversationID: conversationID,
                        rolloutPath: rolloutPath?.isEmpty == false ? rolloutPath : nil
                    )
                }
                conversationSemaphore.signal()
            }
        }

        let handleStderrLine: @Sendable (String) -> Void = { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            if line.hasPrefix("WARNING: proceeding, even though we could not update PATH") {
                return
            }
            state.lock.withLock {
                state.stderrLines.append(line)
                if state.stderrLines.count > 8 {
                    state.stderrLines.removeFirst(state.stderrLines.count - 8)
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            let lines: [String] = state.lock.withLock {
                state.stdoutBuffer.append(data)
                return Self.consumeLines(from: &state.stdoutBuffer)
            }
            for line in lines {
                handleStdoutLine(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }

            let lines: [String] = state.lock.withLock {
                state.stderrBuffer.append(data)
                return Self.consumeLines(from: &state.stderrBuffer)
            }
            for line in lines {
                handleStderrLine(line)
            }
        }

        do {
            try process.run()
        } catch {
            throw CodexConversationBootstrapError.launchFailed(error.localizedDescription)
        }

        defer {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            if process.isRunning {
                process.terminate()
            }
        }

        let initializeRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": RequestID.initialize,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "AgentOS",
                    "version": "1.0.0",
                ],
                "capabilities": NSNull(),
            ],
        ]
        try Self.sendJSONObject(initializeRequest, via: stdinPipe.fileHandleForWriting)

        let initWait = initializeSemaphore.wait(timeout: .now() + max(timeout / 2.0, 2.0))
        if initWait == .timedOut {
            throw CodexConversationBootstrapError.protocolTimedOut("initialize")
        }
        if let initializeError = state.lock.withLock({ state.initializeError }) {
            throw CodexConversationBootstrapError.protocolError(initializeError)
        }

        let initializedNotification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:],
        ]
        try Self.sendJSONObject(initializedNotification, via: stdinPipe.fileHandleForWriting)

        let newConversationRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": RequestID.newConversation,
            "method": "newConversation",
            "params": [
                "cwd": workingDirectory,
            ],
        ]
        try Self.sendJSONObject(newConversationRequest, via: stdinPipe.fileHandleForWriting)

        let conversationWait = conversationSemaphore.wait(timeout: .now() + timeout)
        if conversationWait == .timedOut {
            throw CodexConversationBootstrapError.protocolTimedOut("newConversation")
        }
        if let bootstrapError = state.lock.withLock({ state.bootstrapError }) {
            throw CodexConversationBootstrapError.protocolError(bootstrapError)
        }
        if let result = state.lock.withLock({ state.result }) {
            return result
        }

        let stderrSummary = state.lock.withLock { state.stderrLines.joined(separator: " | ") }
        if !stderrSummary.isEmpty {
            throw CodexConversationBootstrapError.invalidResponse(stderrSummary)
        }

        throw CodexConversationBootstrapError.invalidResponse("未收到可用的 newConversation 响应")
    }

    private static func sendJSONObject(_ object: [String: Any], via handle: FileHandle) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CodexConversationBootstrapError.invalidResponse("请求对象不是有效 JSON")
        }
        let payload = try JSONSerialization.data(withJSONObject: object, options: [])
        var framed = payload
        framed.append(0x0A)
        try handle.write(contentsOf: framed)
    }

    private static func parseRequestID(_ raw: Any?) -> Int? {
        if let intValue = raw as? Int {
            return intValue
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let string = raw as? String {
            return Int(string)
        }
        return nil
    }

    private static func consumeLines(from buffer: inout Data) -> [String] {
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)

            var sanitizedLineData = lineData
            if sanitizedLineData.last == 0x0D {
                sanitizedLineData.removeLast()
            }
            guard !sanitizedLineData.isEmpty else { continue }
            lines.append(String(decoding: sanitizedLineData, as: UTF8.self))
        }
        return lines
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
