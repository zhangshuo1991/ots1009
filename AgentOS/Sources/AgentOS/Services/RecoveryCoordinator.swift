import Foundation

final class RecoveryCoordinator {
    private let persistence: SessionPersistence

    init(persistence: SessionPersistence) {
        self.persistence = persistence
    }

    func restore() -> WorkspaceSnapshot? {
        do {
            return try persistence.load()
        } catch {
            return nil
        }
    }

    func persist(_ snapshot: WorkspaceSnapshot) {
        do {
            try persistence.save(snapshot)
        } catch {
            // 持久化失败不应阻断主流程，UI 会继续可用。
        }
    }
}
