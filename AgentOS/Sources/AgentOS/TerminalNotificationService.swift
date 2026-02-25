import Foundation
import UserNotifications

protocol TerminalNotificationServiceProtocol {
    func requestAuthorizationIfNeeded()
    func notifySessionCompleted(_ session: CLITerminalSession)
}

final class TerminalNotificationService: TerminalNotificationServiceProtocol {
    private let center: UNUserNotificationCenter
    private var hasRequestedAuthorization = false

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true

        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            // Silent failure; app keeps running even if user denies notifications.
        }
    }

    func notifySessionCompleted(_ session: CLITerminalSession) {
        let content = UNMutableNotificationContent()
        content.title = "\(session.tool.title) 任务完成"

        if let exitCode = session.exitCode {
            if exitCode == 0 {
                content.body = "会话已完成，退出码 0"
            } else {
                content.body = "会话已结束，退出码 \(exitCode)"
            }
        } else {
            content.body = "会话已结束"
        }

        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "cli-session-\(session.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}


struct NoopTerminalNotificationService: TerminalNotificationServiceProtocol {
    func requestAuthorizationIfNeeded() {}
    func notifySessionCompleted(_ session: CLITerminalSession) {}
}
