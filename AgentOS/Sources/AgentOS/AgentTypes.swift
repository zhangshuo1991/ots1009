import Foundation

enum AgentKind: String, CaseIterable, Identifiable, Codable {
    case codex
    case claude
    case gemini
    case opencode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .gemini: return "Gemini CLI"
        case .opencode: return "OpenCode"
        }
    }

    var models: [String] {
        switch self {
        case .codex:
            return ["gpt-5-codex", "gpt-5", "gpt-4.1"]
        case .claude:
            return ["claude-sonnet-4-5", "claude-opus-4-1", "claude-haiku-4-5"]
        case .gemini:
            return ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"]
        case .opencode:
            return ["anthropic/claude-sonnet-4", "openai/gpt-5-codex", "google/gemini-2.5-pro"]
        }
    }
}

enum RunMode: String, CaseIterable, Identifiable, Codable {
    case local
    case scenario

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地执行"
        case .scenario: return "场景模拟"
        }
    }
}

enum SessionStep: String, CaseIterable, Identifiable, Codable {
    case draft
    case running
    case reviewing
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "草稿"
        case .running: return "执行中"
        case .reviewing: return "待审批"
        case .done: return "已完成"
        }
    }
}

struct SessionEvent: Identifiable, Hashable, Codable {
    let id: UUID
    let time: Date
    let actor: String
    let message: String

    init(id: UUID = UUID(), time: Date = Date(), actor: String, message: String) {
        self.id = id
        self.time = time
        self.actor = actor
        self.message = message
    }
}
