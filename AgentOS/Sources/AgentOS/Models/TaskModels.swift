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
    var projectID: UUID?
    var repositoryPath: String
    var branchName: String
    var lane: BoardLane
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
    var comments: [TaskComment]
    var summary: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        projectID: UUID? = nil,
        repositoryPath: String = "",
        branchName: String = "main",
        lane: BoardLane = .backlog,
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
        comments: [TaskComment] = [],
        summary: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.repositoryPath = repositoryPath
        self.branchName = branchName
        self.lane = lane
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
        self.comments = comments
        self.summary = summary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectID
        case repositoryPath
        case branchName
        case lane
        case title
        case goal
        case constraints
        case acceptanceCriteria
        case riskNotes
        case phase
        case phaseHistory
        case status
        case sessions
        case budget
        case validation
        case approval
        case governancePolicy
        case recoveryPoints
        case comments
        case summary
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectID = try container.decodeIfPresent(UUID.self, forKey: .projectID)
        repositoryPath = try container.decodeIfPresent(String.self, forKey: .repositoryPath) ?? ""
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName) ?? "main"
        lane = try container.decodeIfPresent(BoardLane.self, forKey: .lane) ?? .backlog
        title = try container.decode(String.self, forKey: .title)
        goal = try container.decode(String.self, forKey: .goal)
        constraints = try container.decode([String].self, forKey: .constraints)
        acceptanceCriteria = try container.decode([String].self, forKey: .acceptanceCriteria)
        riskNotes = try container.decode([String].self, forKey: .riskNotes)
        phase = try container.decodeIfPresent(TaskPhase.self, forKey: .phase) ?? .plan
        phaseHistory = try container.decodeIfPresent([TaskPhase].self, forKey: .phaseHistory) ?? [.plan]
        status = try container.decodeIfPresent(TaskStatus.self, forKey: .status) ?? .ready
        sessions = try container.decodeIfPresent([AgentSession].self, forKey: .sessions) ?? []
        budget = try container.decodeIfPresent(BudgetTracker.self, forKey: .budget) ?? .default
        validation = try container.decodeIfPresent(ValidationSnapshot.self, forKey: .validation) ?? .default
        approval = try container.decodeIfPresent(ApprovalState.self, forKey: .approval) ?? .default
        governancePolicy = try container.decodeIfPresent(GovernancePolicy.self, forKey: .governancePolicy) ?? .defaults(for: .balanced)
        recoveryPoints = try container.decodeIfPresent([RecoveryPoint].self, forKey: .recoveryPoints) ?? []
        comments = try container.decodeIfPresent([TaskComment].self, forKey: .comments) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encode(repositoryPath, forKey: .repositoryPath)
        try container.encode(branchName, forKey: .branchName)
        try container.encode(lane, forKey: .lane)
        try container.encode(title, forKey: .title)
        try container.encode(goal, forKey: .goal)
        try container.encode(constraints, forKey: .constraints)
        try container.encode(acceptanceCriteria, forKey: .acceptanceCriteria)
        try container.encode(riskNotes, forKey: .riskNotes)
        try container.encode(phase, forKey: .phase)
        try container.encode(phaseHistory, forKey: .phaseHistory)
        try container.encode(status, forKey: .status)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(budget, forKey: .budget)
        try container.encode(validation, forKey: .validation)
        try container.encode(approval, forKey: .approval)
        try container.encode(governancePolicy, forKey: .governancePolicy)
        try container.encode(recoveryPoints, forKey: .recoveryPoints)
        try container.encode(comments, forKey: .comments)
        try container.encode(summary, forKey: .summary)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}
