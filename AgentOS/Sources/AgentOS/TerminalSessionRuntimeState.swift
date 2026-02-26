import Foundation

enum TerminalSessionRuntimeState: String, Codable, Sendable {
    case syncing
    case working
    case waitingUserInput
    case waitingApproval
    case unknown
    case completedSuccess
    case completedFailure
    case restoredStopped
    case stopped

    var tabLabel: String {
        switch self {
        case .syncing:
            return "同步中"
        case .working:
            return "工作中"
        case .waitingUserInput:
            return "等待输入"
        case .waitingApproval:
            return "等待授权"
        case .unknown:
            return "状态未知"
        case .completedSuccess:
            return "已完成"
        case .completedFailure:
            return "失败"
        case .restoredStopped:
            return "已恢复"
        case .stopped:
            return "已停止"
        }
    }

    var detailLabel: String {
        switch self {
        case .syncing:
            return "运行中（同步中）"
        case .working:
            return "运行中（工作中）"
        case .waitingUserInput:
            return "运行中（等待输入）"
        case .waitingApproval:
            return "运行中（等待授权）"
        case .unknown:
            return "运行中（状态未知）"
        case .completedSuccess:
            return "已完成"
        case .completedFailure:
            return "执行失败"
        case .restoredStopped:
            return "已恢复（未运行）"
        case .stopped:
            return "已停止"
        }
    }
}

enum TerminalRuntimeSignalSource: String, Codable, Sendable {
    case lifecycle
    case protocolEvent
    case wrapperIPC
    case runtimeHint
    case heuristicOutput
    case userInput
    case fallback

    var priority: Int {
        switch self {
        case .lifecycle:
            return 1_000
        case .protocolEvent:
            return 900
        case .wrapperIPC:
            return 800
        case .runtimeHint:
            return 600
        case .heuristicOutput:
            return 400
        case .userInput:
            return 150
        case .fallback:
            return 100
        }
    }

    var shortLabel: String {
        switch self {
        case .lifecycle:
            return "系统"
        case .protocolEvent:
            return "协议"
        case .wrapperIPC:
            return "IPC"
        case .runtimeHint:
            return "Hint"
        case .heuristicOutput:
            return "文本"
        case .userInput:
            return "输入"
        case .fallback:
            return "默认"
        }
    }
}

struct TerminalSessionStateClassifier {
    private static let approvalSignals: [String] = [
        "approval required",
        "requires approval",
        "awaiting approval",
        "confirm execution",
        "allow this command",
        "approve this action",
        "permission required",
        "grant permission",
        "是否允许",
        "需要授权",
        "等待授权",
        "请批准",
        "批准执行",
    ]

    private static let inputSignals: [String] = [
        "waiting for input",
        "awaiting user input",
        "awaiting input",
        "press enter to continue",
        "input required",
        "enter your choice",
        "请输入",
        "等待输入",
        "等待用户输入",
        "请选择",
        "输入后回车",
    ]

    static func classify(outputChunk: Data) -> TerminalSessionRuntimeState? {
        guard !outputChunk.isEmpty else { return nil }
        return classify(text: String(decoding: outputChunk, as: UTF8.self))
    }

    static func classify(text: String) -> TerminalSessionRuntimeState? {
        let sanitized = stripANSIForPreview(text)
        let normalized = sanitized
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if approvalSignals.contains(where: normalized.contains) {
            return .waitingApproval
        }
        if inputSignals.contains(where: normalized.contains) {
            return .waitingUserInput
        }
        if looksLikePromptTail(sanitized) {
            return .waitingUserInput
        }
        return nil
    }

    private static func looksLikePromptTail(_ text: String) -> Bool {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lastLine = normalizedText
            .components(separatedBy: .newlines)
            .reversed()
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let promptLine = stripLeadingPromptNoise(lastLine)
        guard !promptLine.isEmpty else { return false }

        if promptLine.hasPrefix("? for shortcuts") || promptLine.hasPrefix("? ") {
            return true
        }

        guard let firstCharacter = promptLine.first else { return false }
        let promptLeadingCharacters: Set<Character> = ["›", "❯", "➜", ">", "$", "%", "#"]
        guard promptLeadingCharacters.contains(firstCharacter) else { return false }

        if firstCharacter == ">" && promptLine.hasPrefix("> ") {
            let markdownQuoteIndicators = ["> - ", "> * ", "> #", "> ##", "> ```"]
            if markdownQuoteIndicators.contains(where: promptLine.hasPrefix) {
                return false
            }
        }

        return promptLine.count <= 240
    }

    private static func stripLeadingPromptNoise(_ text: String) -> String {
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index].unicodeScalars.first!
            let isWhitespaceOrControl = CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
            let isFormattingMarker = scalar == "\u{200B}"
                || scalar == "\u{200C}"
                || scalar == "\u{200D}"
                || scalar == "\u{FEFF}"
            if isWhitespaceOrControl || isFormattingMarker {
                index = text.index(after: index)
                continue
            }
            break
        }
        return String(text[index...])
    }
}
