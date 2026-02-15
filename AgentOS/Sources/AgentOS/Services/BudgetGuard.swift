import Foundation

struct BudgetGuard {
    func applyStrategyTemplate(
        mode: QualityMode,
        budget: inout BudgetTracker,
        policy: GovernancePolicy
    ) {
        switch mode {
        case .fast:
            budget.tokenLimit = 160_000
            budget.costLimit = 60
            budget.runtimeLimitSeconds = 4_800
        case .balanced:
            budget.tokenLimit = 120_000
            budget.costLimit = 40
            budget.runtimeLimitSeconds = 3_600
        case .steady:
            budget.tokenLimit = 90_000
            budget.costLimit = 30
            budget.runtimeLimitSeconds = 3_000
        }

        if let warningThresholdOverride = policy.warningThresholdOverride {
            budget.warningThreshold = warningThresholdOverride
        }
    }

    func warnings(for task: WorkTask) -> [String] {
        var messages: [String] = []
        let budget = task.budget
        let warningThreshold = dynamicWarningThreshold(for: task)
        let criticalThreshold = task.governancePolicy.criticalThreshold

        if budget.tokenUsageRatio >= 1 {
            messages.append("Token 已达到上限，建议切换低成本策略或拆分任务。")
        } else if budget.tokenUsageRatio >= criticalThreshold {
            messages.append("Token 已进入临界区（\(Int(budget.tokenUsageRatio * 100))%），建议立即降级。")
        } else if budget.tokenUsageRatio >= warningThreshold {
            messages.append("Token 使用接近上限（\(Int(budget.tokenUsageRatio * 100))%）。")
        }

        if budget.costUsageRatio >= 1 {
            messages.append("成本预算已耗尽，建议暂停并调整执行策略。")
        } else if budget.costUsageRatio >= criticalThreshold {
            messages.append("成本预算已进入临界区（\(Int(budget.costUsageRatio * 100))%），建议立即处置。")
        } else if budget.costUsageRatio >= warningThreshold {
            messages.append("成本预算接近上限（\(Int(budget.costUsageRatio * 100))%）。")
        }

        if budget.runtimeUsageRatio >= 1 {
            messages.append("执行时长超限，请进行中断恢复或阶段拆分。")
        } else if budget.runtimeUsageRatio >= criticalThreshold {
            messages.append("执行时长进入临界区（\(Int(budget.runtimeUsageRatio * 100))%），请立即决策。")
        } else if budget.runtimeUsageRatio >= warningThreshold {
            messages.append("执行时长接近上限（\(Int(budget.runtimeUsageRatio * 100))%）。")
        }

        if task.sessions.contains(where: { $0.state == .waitingApproval }) {
            messages.append("存在等待授权的代理会话，请及时处理决策门。")
        }

        return messages
    }

    private func dynamicWarningThreshold(for task: WorkTask) -> Double {
        var threshold = task.governancePolicy.warningThresholdOverride ?? task.budget.warningThreshold

        if task.status == .inProgress && task.sessions.count >= 3 {
            threshold -= 0.03
        }
        if task.approval.timeoutAt != nil {
            threshold -= 0.02
        }
        if task.phase == .review || task.phase == .accept {
            threshold -= 0.02
        }

        return max(0.65, min(0.95, threshold))
    }
}
