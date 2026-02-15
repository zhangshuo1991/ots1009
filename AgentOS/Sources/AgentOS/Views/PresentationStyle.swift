import SwiftUI

extension AgentKind {
    var tintColor: Color {
        switch self {
        case .codex: return Color(red: 0.12, green: 0.45, blue: 0.92)
        case .claudeCode: return Color(red: 0.88, green: 0.41, blue: 0.16)
        case .geminiCLI: return Color(red: 0.11, green: 0.62, blue: 0.44)
        case .openCode: return Color(red: 0.54, green: 0.33, blue: 0.78)
        }
    }
}

extension TaskStatus {
    var displayTitle: String {
        switch self {
        case .ready: return "待开始"
        case .inProgress: return "进行中"
        case .paused: return "已暂停"
        case .needsDecision: return "待决策"
        case .failed: return "失败"
        case .completed: return "已完成"
        }
    }

    var tintColor: Color {
        switch self {
        case .ready: return .gray
        case .inProgress: return .yellow
        case .paused: return .orange
        case .needsDecision: return .red
        case .failed: return .red
        case .completed: return .green
        }
    }
}

extension AgentSessionState {
    var displayTitle: String {
        switch self {
        case .idle: return "空闲"
        case .running: return "运行中"
        case .waitingApproval: return "待授权"
        case .blocked: return "阻塞"
        case .failed: return "失败"
        case .completed: return "完成"
        case .cancelled: return "已取消"
        }
    }

    var tintColor: Color {
        switch self {
        case .idle: return .gray
        case .running: return .yellow
        case .waitingApproval: return .red
        case .blocked: return .orange
        case .failed: return .red
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}

extension BoardLane {
    var tintColor: Color {
        switch self {
        case .backlog: return .gray
        case .inProgress: return .blue
        case .review: return .orange
        case .done: return .green
        }
    }
}

extension CollaborationRole {
    var tintColor: Color {
        switch self {
        case .owner: return .blue
        case .developer: return .purple
        case .reviewer: return .orange
        case .qa: return .green
        case .system: return .gray
        }
    }
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.80))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}
