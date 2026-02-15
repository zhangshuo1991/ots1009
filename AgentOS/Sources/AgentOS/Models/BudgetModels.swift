import Foundation

enum QualityMode: String, Codable, CaseIterable {
    case fast
    case balanced
    case steady

    var title: String {
        switch self {
        case .fast: return "极速"
        case .balanced: return "均衡"
        case .steady: return "稳健"
        }
    }
}

struct StrategyProfile: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var mode: QualityMode
    var maxParallelAgents: Int
    var autoAdvance: Bool
    var summary: String

    init(
        id: UUID = UUID(),
        name: String,
        mode: QualityMode,
        maxParallelAgents: Int,
        autoAdvance: Bool,
        summary: String
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.maxParallelAgents = maxParallelAgents
        self.autoAdvance = autoAdvance
        self.summary = summary
    }

    static let presets: [StrategyProfile] = [
        StrategyProfile(
            name: "极速交付",
            mode: .fast,
            maxParallelAgents: 4,
            autoAdvance: true,
            summary: "优先速度，允许更高并发与更少人工确认。"
        ),
        StrategyProfile(
            name: "均衡默认",
            mode: .balanced,
            maxParallelAgents: 3,
            autoAdvance: true,
            summary: "速度与稳定性平衡，适合作为日常默认策略。"
        ),
        StrategyProfile(
            name: "稳健验收",
            mode: .steady,
            maxParallelAgents: 2,
            autoAdvance: false,
            summary: "优先质量与可控性，关键阶段需要人工推进。"
        ),
    ]
}

struct BudgetTracker: Codable, Hashable {
    var tokenUsed: Int
    var tokenLimit: Int
    var costUsed: Double
    var costLimit: Double
    var runtimeSeconds: Int
    var runtimeLimitSeconds: Int
    var warningThreshold: Double

    static let `default` = BudgetTracker(
        tokenUsed: 0,
        tokenLimit: 120_000,
        costUsed: 0,
        costLimit: 40,
        runtimeSeconds: 0,
        runtimeLimitSeconds: 3_600,
        warningThreshold: 0.8
    )

    var tokenUsageRatio: Double {
        guard tokenLimit > 0 else { return 0 }
        return min(1, Double(tokenUsed) / Double(tokenLimit))
    }

    var costUsageRatio: Double {
        guard costLimit > 0 else { return 0 }
        return min(1, costUsed / costLimit)
    }

    var runtimeUsageRatio: Double {
        guard runtimeLimitSeconds > 0 else { return 0 }
        return min(1, Double(runtimeSeconds) / Double(runtimeLimitSeconds))
    }
}
