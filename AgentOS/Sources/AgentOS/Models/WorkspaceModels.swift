import Foundation

enum BoardLane: String, Codable, CaseIterable, Hashable, Identifiable {
    case backlog
    case inProgress
    case review
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backlog: return "待办"
        case .inProgress: return "进行中"
        case .review: return "待评审"
        case .done: return "已完成"
        }
    }
}

enum CollaborationRole: String, Codable, CaseIterable, Hashable, Identifiable {
    case owner
    case developer
    case reviewer
    case qa
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "Owner"
        case .developer: return "Developer"
        case .reviewer: return "Reviewer"
        case .qa: return "QA"
        case .system: return "System"
        }
    }
}

struct TaskComment: Codable, Hashable, Identifiable {
    let id: UUID
    var author: CollaborationRole
    var content: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        author: CollaborationRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.content = content
        self.createdAt = createdAt
    }
}

struct WorkspaceProject: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var repositoryPath: String
    var defaultBranch: String
    var activeBranch: String
    var taskIDs: [UUID]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        repositoryPath: String,
        defaultBranch: String = "main",
        activeBranch: String = "main",
        taskIDs: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repositoryPath = repositoryPath
        self.defaultBranch = defaultBranch
        self.activeBranch = activeBranch
        self.taskIDs = taskIDs
        self.createdAt = createdAt
    }
}
