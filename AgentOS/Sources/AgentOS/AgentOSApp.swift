import Foundation
import SwiftUI

@main
struct AgentOSApp: App {
    @State private var state = AppState(
        terminalNotificationService: TerminalNotificationService(),
        userDefaults: .standard,
        isTerminalWorkspacePersistenceEnabled: true
    )

    var body: some Scene {
        Window("编程工具管理器", id: "main") {
            MainView(state: state)
                .preferredColorScheme(.light)
                .tint(DesignTokens.ColorToken.brandPrimary)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 760)
        .commands {
            TerminalWorkspaceCommands(state: state)
        }
    }
}

private struct TerminalWorkspaceCommands: Commands {
    var state: AppState

    var body: some Commands {
        CommandMenu("终端") {
            Button("新建终端会话") {
                _ = state.createTerminalSessionWithDirectorySelection()
            }
            .keyboardShortcut("t", modifiers: [.command])

            Button("关闭当前会话") {
                _ = state.closeCurrentTerminalSession()
            }
            .keyboardShortcut("w", modifiers: [.command])
            .disabled(state.terminalSessions.isEmpty)

            Button("恢复最近关闭会话") {
                _ = state.reopenLastClosedTerminalSession()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(state.recentlyClosedTerminalSessions.isEmpty)
        }
    }
}
