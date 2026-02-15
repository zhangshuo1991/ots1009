import Foundation

enum TaskPhase: String, Codable, CaseIterable {
    case plan
    case implement
    case selfCheck
    case review
    case accept

    var title: String {
        switch self {
        case .plan: return "计划"
        case .implement: return "实施"
        case .selfCheck: return "自检"
        case .review: return "评审"
        case .accept: return "验收"
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable {
    case ready
    case inProgress
    case paused
    case needsDecision
    case failed
    case completed
}

struct ValidationSnapshot: Codable, Hashable {
    var testsPassed: Bool
    var lintPassed: Bool
    var reviewPassed: Bool
    var acceptancePassed: Bool
    var hasConflict: Bool

    static let `default` = ValidationSnapshot(
        testsPassed: false,
        lintPassed: false,
        reviewPassed: false,
        acceptancePassed: false,
        hasConflict: false
    )
}

struct TaskCheckpoint: Codable, Hashable {
    var phase: TaskPhase
    var phaseHistory: [TaskPhase]
    var status: TaskStatus
    var sessions: [AgentSession]
    var budget: BudgetTracker
    var validation: ValidationSnapshot
    var approval: ApprovalState
    var summary: String
}

struct RecoveryPoint: Codable, Hashable, Identifiable {
    let id: UUID
    let createdAt: Date
    let note: String
    let checkpoint: TaskCheckpoint?

    init(id: UUID = UUID(), createdAt: Date = Date(), note: String, checkpoint: TaskCheckpoint? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.note = note
        self.checkpoint = checkpoint
    }
}

struct AgentSession: Codable, Hashable, Identifiable {
    let id: UUID
    let agent: AgentKind
    var command: String
    var state: AgentSessionState
    var startedAt: Date
    var finishedAt: Date?
    var latestMessage: String
    var output: [String]
    var estimatedTokens: Int
    var estimatedCost: Double
    var failureCategory: FailureCategory?
    var recommendedRecovery: RecoveryAction?
    var recoveredAt: Date?

    init(
        id: UUID = UUID(),
        agent: AgentKind,
        command: String,
        state: AgentSessionState = .idle,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        latestMessage: String = "",
        output: [String] = [],
        estimatedTokens: Int = 0,
        estimatedCost: Double = 0,
        failureCategory: FailureCategory? = nil,
        recommendedRecovery: RecoveryAction? = nil,
        recoveredAt: Date? = nil
    ) {
        self.id = id
        self.agent = agent
        self.command = command
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.latestMessage = latestMessage
        self.output = output
        self.estimatedTokens = estimatedTokens
        self.estimatedCost = estimatedCost
        self.failureCategory = failureCategory
        self.recommendedRecovery = recommendedRecovery
        self.recoveredAt = recoveredAt
    }
}

struct WorkTask: Codable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var goal: String
    var constraints: [String]
    var acceptanceCriteria: [String]
    var riskNotes: [String]
    var phase: TaskPhase
    var phaseHistory: [TaskPhase]
    var status: TaskStatus
    var sessions: [AgentSession]
    var budget: BudgetTracker
    var validation: ValidationSnapshot
    var approval: ApprovalState
    var governancePolicy: GovernancePolicy
    var recoveryPoints: [RecoveryPoint]
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        goal: String,
        constraints: [String],
        acceptanceCriteria: [String],
        riskNotes: [String],
        phase: TaskPhase = .plan,
        phaseHistory: [TaskPhase] = [.plan],
        status: TaskStatus = .ready,
        sessions: [AgentSession] = [],
        budget: BudgetTracker = .default,
        validation: ValidationSnapshot = .default,
        approval: ApprovalState = .default,
        governancePolicy: GovernancePolicy = .defaults(for: .balanced),
        recoveryPoints: [RecoveryPoint] = [],
        summary: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.goal = goal
        self.constraints = constraints
        self.acceptanceCriteria = acceptanceCriteria
        self.riskNotes = riskNotes
        self.phase = phase
        self.phaseHistory = phaseHistory
        self.status = status
        self.sessions = sessions
        self.budget = budget
        self.validation = validation
        self.approval = approval
        self.governancePolicy = governancePolicy
        self.recoveryPoints = recoveryPoints
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
