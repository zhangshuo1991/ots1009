import Foundation

enum AlertSeverity: String, Codable, CaseIterable {
    case info
    case warning
    case critical
}

enum ApprovalRole: String, Codable, CaseIterable, Identifiable, Hashable {
    case owner
    case approver
    case observer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "Owner"
        case .approver: return "Approver"
        case .observer: return "Observer"
        }
    }
}

enum ApprovalFallbackAction: String, Codable, CaseIterable {
    case autoApprove
    case autoBlock

    var title: String {
        switch self {
        case .autoApprove: return "超时自动放行"
        case .autoBlock: return "超时自动阻塞"
        }
    }
}

enum FailureCategory: String, Codable, CaseIterable {
    case permissionDenied
    case timeout
    case runtimeError
    case cancelled
    case unknown

    var title: String {
        switch self {
        case .permissionDenied: return "权限失败"
        case .timeout: return "执行超时"
        case .runtimeError: return "运行错误"
        case .cancelled: return "人工取消"
        case .unknown: return "未知异常"
        }
    }
}

enum RecoveryAction: String, Codable, CaseIterable {
    case retry
    case rollback
    case manualInspection

    var title: String {
        switch self {
        case .retry: return "重试会话"
        case .rollback: return "回滚恢复点"
        case .manualInspection: return "人工排查"
        }
    }
}

struct ApprovalState: Codable, Hashable {
    var requiredApprovals: Int
    var approverRoles: [ApprovalRole]
    var grantedApprovals: [ApprovalRole]
    var timeoutAt: Date?
    var fallbackAction: ApprovalFallbackAction
    var isResolved: Bool

    static let `default` = ApprovalState(
        requiredApprovals: 1,
        approverRoles: [.owner, .approver],
        grantedApprovals: [],
        timeoutAt: nil,
        fallbackAction: .autoBlock,
        isResolved: false
    )
}

struct GovernancePolicy: Codable, Hashable {
    var requiredApprovals: Int
    var timeoutSeconds: Int
    var fallbackAction: ApprovalFallbackAction
    var warningThresholdOverride: Double?
    var criticalThreshold: Double

    static func defaults(for mode: QualityMode) -> GovernancePolicy {
        switch mode {
        case .fast:
            return GovernancePolicy(
                requiredApprovals: 1,
                timeoutSeconds: 25,
                fallbackAction: .autoApprove,
                warningThresholdOverride: 0.85,
                criticalThreshold: 0.96
            )
        case .balanced:
            return GovernancePolicy(
                requiredApprovals: 1,
                timeoutSeconds: 40,
                fallbackAction: .autoBlock,
                warningThresholdOverride: 0.8,
                criticalThreshold: 0.93
            )
        case .steady:
            return GovernancePolicy(
                requiredApprovals: 2,
                timeoutSeconds: 60,
                fallbackAction: .autoBlock,
                warningThresholdOverride: 0.75,
                criticalThreshold: 0.9
            )
        }
    }
}

struct DeliveryMetrics: Codable, Hashable {
    var recoveryAverageSeconds: Int
    var budgetDeviationPercent: Int
    var validationPassRatePercent: Int

    static let zero = DeliveryMetrics(
        recoveryAverageSeconds: 0,
        budgetDeviationPercent: 0,
        validationPassRatePercent: 0
    )
}

