import Darwin
import Foundation

final class TerminalSessionOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maxBytes: Int
    private let maxPreviewCharacters: Int

    private var storage = Data()
    private var droppedByteCount = 0
    private var previewWindow = ""

    init(initialData: Data = Data(), maxBytes: Int = 1_200_000, maxPreviewCharacters: Int = 4_096) {
        self.maxBytes = maxBytes
        self.maxPreviewCharacters = maxPreviewCharacters
        replace(with: initialData)
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }

        lock.lock()
        storage.append(chunk)
        truncateStorageIfNeeded()
        previewWindow.append(String(decoding: chunk, as: UTF8.self))
        truncatePreviewIfNeeded()
        lock.unlock()
    }

    func replace(with newData: Data) {
        lock.lock()
        storage = newData
        droppedByteCount = 0
        truncateStorageIfNeeded()
        previewWindow = String(decoding: storage, as: UTF8.self)
        truncatePreviewIfNeeded()
        lock.unlock()
    }

    func clear() {
        replace(with: Data())
    }

    func snapshotData() -> Data {
        lock.lock()
        let value = storage
        lock.unlock()
        return value
    }

    func snapshotText() -> String {
        String(decoding: snapshotData(), as: UTF8.self)
    }

    func previewText() -> String {
        lock.lock()
        let previewSource = previewWindow
        lock.unlock()

        let rendered = stripANSIForPreview(previewSource)
        let lines = rendered
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return lines.suffix(4).joined(separator: "\n")
    }

    func renderDelta(from cursor: Int) -> (delta: Data, nextCursor: Int, shouldReset: Bool) {
        lock.lock()
        defer { lock.unlock() }

        let availableStart = droppedByteCount
        let availableEnd = droppedByteCount + storage.count

        if cursor < availableStart {
            return (storage, availableEnd, true)
        }
        if cursor > availableEnd {
            return (storage, availableEnd, true)
        }

        let localOffset = max(cursor - availableStart, 0)
        if localOffset >= storage.count {
            return (Data(), availableEnd, false)
        }

        let start = storage.index(storage.startIndex, offsetBy: localOffset)
        let delta = storage.subdata(in: start..<storage.endIndex)
        return (delta, availableEnd, false)
    }

    func initialRenderCursor() -> Int {
        lock.lock()
        let value = droppedByteCount
        lock.unlock()
        return value
    }

    private func truncateStorageIfNeeded() {
        guard maxBytes > 0 else {
            droppedByteCount += storage.count
            storage = Data()
            return
        }
        guard storage.count > maxBytes else { return }

        var truncated = Data(storage.suffix(maxBytes))
        if let boundaryIndex = truncated.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let nextIndex = truncated.index(after: boundaryIndex)
            if nextIndex < truncated.endIndex {
                truncated.removeSubrange(..<nextIndex)
            }
        }

        let removedBytes = max(storage.count - truncated.count, 0)
        droppedByteCount += removedBytes
        storage = truncated
    }

    private func truncatePreviewIfNeeded() {
        guard maxPreviewCharacters > 0 else {
            previewWindow = ""
            return
        }
        guard previewWindow.count > maxPreviewCharacters else { return }
        previewWindow = String(previewWindow.suffix(maxPreviewCharacters))
    }
}

struct CLITerminalSession: Identifiable, Equatable {
    let id: UUID
    let tool: ProgrammingTool
    var title: String
    let executable: String
    let arguments: [String]
    var workingDirectory: String
    var createdAt: Date
    var updatedAt: Date
    var startedAt: Date
    var endedAt: Date?
    var isRunning: Bool
    var exitCode: Int32?
    let outputBuffer: TerminalSessionOutputBuffer
    var lastInput: String?
    var isRestoredSnapshot: Bool
    var transcriptFilePath: String?
    var codexConversationID: String? = nil

    var commandLine: String {
        ([executable] + arguments).joined(separator: " ")
    }

    var statusText: String {
        if isRunning {
            return "运行中"
        }
        if isRestoredSnapshot {
            return "已恢复（未运行）"
        }
        if let exitCode {
            return exitCode == 0 ? "已完成" : "退出码 \(exitCode)"
        }
        return "已停止"
    }

    var statusColorState: ConfigurationValueState {
        if isRunning {
            return .informational
        }
        if let exitCode {
            return exitCode == 0 ? .configured : .warning
        }
        return .missing
    }

    var output: String {
        get { outputBuffer.snapshotText() }
        set { outputBuffer.replace(with: Data(newValue.utf8)) }
    }

    var outputData: Data {
        get { outputBuffer.snapshotData() }
        set { outputBuffer.replace(with: newValue) }
    }

    var outputPreview: String {
        outputBuffer.previewText()
    }

    static func == (lhs: CLITerminalSession, rhs: CLITerminalSession) -> Bool {
        lhs.id == rhs.id &&
            lhs.tool == rhs.tool &&
            lhs.title == rhs.title &&
            lhs.executable == rhs.executable &&
            lhs.arguments == rhs.arguments &&
            lhs.workingDirectory == rhs.workingDirectory &&
            lhs.createdAt == rhs.createdAt &&
            lhs.updatedAt == rhs.updatedAt &&
            lhs.startedAt == rhs.startedAt &&
            lhs.endedAt == rhs.endedAt &&
            lhs.isRunning == rhs.isRunning &&
            lhs.exitCode == rhs.exitCode &&
            lhs.outputData == rhs.outputData &&
            lhs.lastInput == rhs.lastInput &&
            lhs.isRestoredSnapshot == rhs.isRestoredSnapshot &&
            lhs.transcriptFilePath == rhs.transcriptFilePath &&
            lhs.codexConversationID == rhs.codexConversationID
    }
}

enum TerminalConsoleFallbackState: Equatable {
    case liveSurface
    case launching
    case transcript(String)
    case unavailable
}

enum TerminalConsoleFallbackResolver {
    static func resolve(
        session: CLITerminalSession,
        hasRunner: Bool,
        maxTranscriptCharacters: Int = 12_000
    ) -> TerminalConsoleFallbackState {
        if hasRunner {
            return .liveSurface
        }
        if session.isRunning {
            return .launching
        }
        guard let transcript = sanitizedTranscript(
            from: session.outputBuffer.snapshotText(),
            maxCharacters: maxTranscriptCharacters
        ) else {
            return .unavailable
        }
        return .transcript(transcript)
    }

    static func sanitizedTranscript(from raw: String, maxCharacters: Int) -> String? {
        let sanitized = stripANSIForPreview(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else { return nil }
        guard maxCharacters > 0 else { return sanitized }
        guard sanitized.count > maxCharacters else { return sanitized }
        return String(sanitized.suffix(maxCharacters))
    }
}

protocol CLITerminalRunning: AnyObject {
    var onOutput: ((Data) -> Void)? { get set }
    var onWorkingDirectoryChange: ((String?) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }

    func start(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws

    func send(data: Data)
    func resize(cols: Int, rows: Int)
    func terminate()
}

protocol RuntimeStateHintingTerminalRunner: CLITerminalRunning {
    var onRuntimeStateHint: ((TerminalSessionRuntimeState) -> Void)? { get set }
}

enum CLITerminalError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            if detail.isEmpty {
                return "终端进程启动失败"
            }
            return "终端进程启动失败：\(detail)"
        }
    }
}

// MARK: - ANSI Stripping

func stripANSIForPreview(_ raw: String) -> String {
    var text = raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")

    let esc = "\u{001B}"
    let patterns = [
        "\(esc)\\[[0-?]*[ -/]*[@-~]",
        "\(esc)\\][^\u{0007}]*\u{0007}",
        "\(esc)\\][^\(esc)]*\(esc)\\\\",
    ]

    for pattern in patterns {
        text = text.replacingOccurrences(
            of: pattern,
            with: "",
            options: .regularExpression
        )
    }

    return text
}
