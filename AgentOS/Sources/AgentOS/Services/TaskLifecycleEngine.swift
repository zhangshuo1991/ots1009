import Foundation

struct TaskLifecycleEngine {
    func canAdvance(_ task: WorkTask) -> Bool {
        switch task.phase {
        case .plan:
            return !task.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .implement:
            return hasAtLeastOneCompletedSession(task)
        case .selfCheck:
            return task.validation.testsPassed && task.validation.lintPassed
        case .review:
            return task.validation.reviewPassed && !task.validation.hasConflict
        case .accept:
            return task.validation.acceptancePassed
        }
    }

    func advance(_ task: inout WorkTask) -> Bool {
        guard canAdvance(task) else { return false }

        switch task.phase {
        case .plan:
            task.phase = .implement
            task.status = .inProgress
        case .implement:
            task.phase = .selfCheck
            task.status = .inProgress
        case .selfCheck:
            task.phase = .review
            task.status = .inProgress
        case .review:
            task.phase = .accept
            task.status = .inProgress
        case .accept:
            task.status = .completed
        }

        if task.phaseHistory.last != task.phase {
            task.phaseHistory.append(task.phase)
        }

        task.updatedAt = Date()
        return true
    }

    func withConflictDecision(_ task: inout WorkTask, hasConflict: Bool) {
        task.validation.hasConflict = hasConflict
        task.status = hasConflict ? .needsDecision : task.status
        task.updatedAt = Date()
    }

    private func hasAtLeastOneCompletedSession(_ task: WorkTask) -> Bool {
        task.sessions.contains { $0.state == .completed }
    }
}
