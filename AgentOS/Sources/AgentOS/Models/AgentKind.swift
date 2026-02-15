import Foundation

enum AgentKind: String, CaseIterable, Codable, Identifiable, Hashable {
    case codex
    case claudeCode
    case geminiCLI
    case openCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .geminiCLI: return "Gemini CLI"
        case .openCode: return "OpenCode"
        }
    }

    var defaultCommand: String {
        switch self {
        case .codex:
            return "echo '[Codex] phase: planning'; sleep 1; echo '[Codex] phase: implementing'; sleep 1; echo '[Codex] done'"
        case .claudeCode:
            return "echo '[ClaudeCode] phase: planning'; sleep 1; echo '[ClaudeCode] phase: refactoring'; sleep 1; echo '[ClaudeCode] done'"
        case .geminiCLI:
            return "echo '[GeminiCLI] phase: investigating'; sleep 1; echo '[GeminiCLI] phase: validating'; sleep 1; echo '[GeminiCLI] done'"
        case .openCode:
            return "echo '[OpenCode] phase: coding'; sleep 1; echo '[OpenCode] phase: checking'; sleep 1; echo '[OpenCode] done'"
        }
    }
}

enum AgentSessionState: String, Codable, CaseIterable {
    case idle
    case running
    case waitingApproval
    case blocked
    case failed
    case completed
    case cancelled
}
