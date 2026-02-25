import Foundation

protocol CodexAppServerMonitoring: AnyObject {
    func start()
    func stop()
}

final class CodexAppServerMonitor: CodexAppServerMonitoring, @unchecked Sendable {
    struct Configuration {
        let conversationID: String
        let workingDirectory: String
        let launchedAt: Date
        let environment: [String: String]
        let onRuntimeState: @Sendable (TerminalSessionRuntimeState) -> Void
        let onError: @Sendable (String) -> Void
    }

    private enum PendingRequestKind {
        case initialize
        case resumeConversation(String)
        case addConversationListener(String)
    }

    private let configuration: Configuration
    private let queue: DispatchQueue

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()

    private var nextRequestID = 1
    private var pendingRequests: [Int: PendingRequestKind] = [:]
    private var isRunning = false
    private var hasSentInitializedNotification = false
    private var boundConversationID: String?
    private var lastEmittedErrorMessage: String?

    init(configuration: Configuration) {
        self.configuration = configuration
        self.queue = DispatchQueue(label: "agentos.codex.appserver.monitor.\(UUID().uuidString)")
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["codex", "app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = URL(fileURLWithPath: configuration.workingDirectory, isDirectory: true)
        process.environment = configuration.environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        process.terminationHandler = { [weak self] _ in
            self?.queue.async {
                self?.handleProcessTerminated()
            }
        }

        do {
            try process.run()
        } catch {
            configuration.onError("Codex app-server 启动失败：\(error.localizedDescription)")
            return
        }

        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutHandle = stdoutPipe.fileHandleForReading
        self.stderrHandle = stderrPipe.fileHandleForReading
        self.isRunning = true

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.handleStdoutData(data)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async {
                self?.handleStderrData(data)
            }
        }

        sendInitializeRequest()
    }

    private func stopOnQueue() {
        guard isRunning || process != nil else { return }

        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil

        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil

        let runningProcess = process
        process = nil
        if let runningProcess, runningProcess.isRunning {
            runningProcess.terminate()
        }

        pendingRequests.removeAll(keepingCapacity: false)
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        hasSentInitializedNotification = false
        boundConversationID = nil
        lastEmittedErrorMessage = nil
        isRunning = false
    }

    private func handleProcessTerminated() {
        guard isRunning else { return }
        stopOnQueue()
    }

    private func sendInitializeRequest() {
        sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "AgentOS",
                    "version": "1.0.0",
                ],
                "capabilities": NSNull(),
            ],
            kind: .initialize
        )
    }

    private func sendInitializedNotificationIfNeeded() {
        guard !hasSentInitializedNotification else { return }
        hasSentInitializedNotification = true
        sendNotification(method: "initialized", params: [:])
    }

    private func sendResumeConversationRequest(_ conversationID: String) {
        sendRequest(
            method: "resumeConversation",
            params: [
                "path": NSNull(),
                "conversationId": conversationID,
                "history": NSNull(),
                "overrides": NSNull(),
            ],
            kind: .resumeConversation(conversationID)
        )
    }

    private func sendAddConversationListenerRequest(_ conversationID: String) {
        sendRequest(
            method: "addConversationListener",
            params: [
                "conversationId": conversationID,
                "experimentalRawEvents": true,
            ],
            kind: .addConversationListener(conversationID)
        )
    }

    private func sendRequest(method: String, params: [String: Any], kind: PendingRequestKind) {
        let requestID = nextRequestID
        nextRequestID += 1
        pendingRequests[requestID] = kind

        sendJSONObject([
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params,
        ])
    }

    private func sendNotification(method: String, params: [String: Any]) {
        sendJSONObject([
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
        ])
    }

    private func sendResponse(id: Any, result: Any) {
        sendJSONObject([
            "jsonrpc": "2.0",
            "id": id,
            "result": result,
        ])
    }

    private func sendJSONObject(_ object: [String: Any]) {
        guard let stdinHandle else { return }
        guard JSONSerialization.isValidJSONObject(object) else { return }
        guard let payload = try? JSONSerialization.data(withJSONObject: object, options: []) else { return }

        var framed = payload
        framed.append(0x0A)
        do {
            try stdinHandle.write(contentsOf: framed)
        } catch {
            configuration.onError("Codex app-server 写入失败：\(error.localizedDescription)")
        }
    }

    private func handleStdoutData(_ data: Data) {
        if data.isEmpty {
            stdoutHandle?.readabilityHandler = nil
            return
        }

        stdoutBuffer.append(data)
        consumeLines(from: &stdoutBuffer, handler: handleStdoutLine)
    }

    private func handleStderrData(_ data: Data) {
        if data.isEmpty {
            stderrHandle?.readabilityHandler = nil
            return
        }

        stderrBuffer.append(data)
        consumeLines(from: &stderrBuffer) { [weak self] line in
            self?.handleStderrLine(line)
        }
    }

    private func consumeLines(from buffer: inout Data, handler: (String) -> Void) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)

            var sanitizedLineData = lineData
            if sanitizedLineData.last == 0x0D {
                sanitizedLineData.removeLast()
            }
            guard !sanitizedLineData.isEmpty else { continue }

            let line = String(decoding: sanitizedLineData, as: UTF8.self)
            handler(line)
        }
    }

    private func handleStderrLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if line.hasPrefix("WARNING: proceeding, even though we could not update PATH") {
            return
        }
        configuration.onError("Codex app-server: \(line)")
    }

    private func handleStdoutLine(_ rawLine: String) {
        guard let data = rawLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let payload = object as? [String: Any]
        else {
            return
        }

        if let method = payload["method"] as? String, !method.isEmpty {
            let params = payload["params"] as? [String: Any]
            if let requestID = payload["id"] {
                handleServerRequest(method: method, requestID: requestID, params: params)
            } else {
                handleNotification(method: method, params: params)
            }
            return
        }

        guard let id = parseRequestID(payload["id"]) else { return }
        let requestKind = pendingRequests.removeValue(forKey: id)
        handleResponse(for: requestKind, payload: payload)
    }

    private func handleResponse(for requestKind: PendingRequestKind?, payload: [String: Any]) {
        guard let requestKind else { return }

        if let errorMessage = rpcErrorMessage(from: payload) {
            handleRPCError(for: requestKind, message: errorMessage)
            return
        }

        switch requestKind {
        case .initialize:
            sendInitializedNotificationIfNeeded()
            sendResumeConversationRequest(configuration.conversationID)

        case .resumeConversation(let conversationID):
            sendAddConversationListenerRequest(conversationID)

        case .addConversationListener(let conversationID):
            boundConversationID = conversationID
            lastEmittedErrorMessage = nil
        }
    }

    private func handleRPCError(for requestKind: PendingRequestKind, message: String) {
        switch requestKind {
        case .initialize:
            emitErrorIfNeeded("Codex 协议初始化失败：\(message)")
            stopOnQueue()
        case .resumeConversation(let conversationID):
            emitErrorIfNeeded("Codex 会话恢复失败（\(conversationID)）：\(message)")
        case .addConversationListener(let conversationID):
            emitErrorIfNeeded("Codex 会话监听失败（\(conversationID)）：\(message)")
        }
    }

    private func handleNotification(method: String, params: [String: Any]?) {
        if let state = runtimeState(forMethod: method, params: params) {
            configuration.onRuntimeState(state)
        }
    }

    private func handleServerRequest(method: String, requestID: Any, params: [String: Any]?) {
        if let state = CodexRuntimeStateMapper.runtimeState(forMethod: method) {
            configuration.onRuntimeState(state)
        }
        sendBestEffortServerResponse(for: method, requestID: requestID, params: params)
    }

    private func runtimeState(forMethod method: String, params: [String: Any]?) -> TerminalSessionRuntimeState? {
        let parsed = parseEventTypeAndConversationID(method: method, params: params)
        let expectedConversationID = boundConversationID ?? configuration.conversationID
        if let incomingConversationID = parsed.conversationID,
           incomingConversationID.caseInsensitiveCompare(expectedConversationID) != .orderedSame {
            return nil
        }
        return CodexRuntimeStateMapper.runtimeState(forMethod: parsed.eventType)
    }

    private func parseEventTypeAndConversationID(
        method: String,
        params: [String: Any]?
    ) -> (eventType: String, conversationID: String?) {
        if method == "codex/event" {
            let eventType = ((params?["msg"] as? [String: Any])?["type"] as? String) ?? method
            let conversationID = extractConversationID(from: params)
            return (eventType, conversationID)
        }

        if method.hasPrefix("codex/event/") {
            let eventType = String(method.dropFirst("codex/event/".count))
            let conversationID = extractConversationID(from: params)
            return (eventType, conversationID)
        }

        return (method, extractConversationID(from: params))
    }

    private func extractConversationID(from params: [String: Any]?) -> String? {
        guard let params else { return nil }

        let knownIDKeys = [
            "conversationId",
            "conversation_id",
            "threadId",
            "thread_id",
            "sessionId",
            "session_id",
        ]

        for key in knownIDKeys {
            if let value = params[key] as? String, !value.isEmpty {
                return value
            }
        }

        if let thread = params["thread"] as? [String: Any],
           let threadID = thread["id"] as? String,
           !threadID.isEmpty {
            return threadID
        }

        if let msg = params["msg"] as? [String: Any] {
            for key in knownIDKeys {
                if let value = msg[key] as? String, !value.isEmpty {
                    return value
                }
            }
            if let thread = msg["thread"] as? [String: Any],
               let threadID = thread["id"] as? String,
               !threadID.isEmpty {
                return threadID
            }
        }

        return nil
    }

    private func sendBestEffortServerResponse(
        for method: String,
        requestID: Any,
        params _: [String: Any]?
    ) {
        let normalized = method.lowercased()
        let result: Any

        switch normalized {
        case "execcommandapproval", "applypatchapproval":
            result = ["decision": "abort"]
        case "item/commandexecution/requestapproval", "item/filechange/requestapproval":
            result = ["decision": "cancel"]
        case "item/tool/requestuserinput":
            result = ["answers": [:]]
        default:
            result = NSNull()
        }

        sendResponse(id: requestID, result: result)
    }

    private func emitErrorIfNeeded(_ message: String) {
        guard !message.isEmpty else { return }
        guard lastEmittedErrorMessage != message else { return }
        lastEmittedErrorMessage = message
        configuration.onError(message)
    }

    private func rpcErrorMessage(from payload: [String: Any]) -> String? {
        guard let error = payload["error"] as? [String: Any] else { return nil }
        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return "未知错误"
    }

    private func parseRequestID(_ raw: Any?) -> Int? {
        if let integer = raw as? Int {
            return integer
        }
        if let number = raw as? NSNumber {
            return number.intValue
        }
        if let string = raw as? String {
            return Int(string)
        }
        return nil
    }
}
