import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var tasks: [WorkTask] = []
    var selectedTaskID: UUID?
    var strategyProfiles: [StrategyProfile] = StrategyProfile.presets
    var selectedStrategyID: UUID?
    var commandTemplates: [AgentKind: String] = Dictionary(
        uniqueKeysWithValues: AgentKind.allCases.map { ($0, $0.defaultCommand) }
    )
    var executionMode: ExecutionMode = .localShell
    var globalMessage: String = ""

    private let lifecycleEngine = TaskLifecycleEngine()
    private let budgetGuard = BudgetGuard()
    private let persistence: SessionPersistence
    private let recoveryCoordinator: RecoveryCoordinator
    @ObservationIgnored private let reportExporter = ReportExporter()
    @ObservationIgnored private var localExecutionProvider: LocalShellExecutionProvider!
    @ObservationIgnored private var scenarioExecutionProvider: ScenarioExecutionProvider!

    init(
        persistence: SessionPersistence = SessionPersistence(),
        scenarioConfig: ScenarioExecutionConfig = .default
    ) {
        self.persistence = persistence
        self.recoveryCoordinator = RecoveryCoordinator(persistence: persistence)

        let sink: @Sendable (AgentExecutionEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleExecutionEvent(event)
            }
        }

        self.localExecutionProvider = LocalShellExecutionProvider(eventSink: sink)
        self.scenarioExecutionProvider = ScenarioExecutionProvider(config: scenarioConfig, eventSink: sink)

        restoreOrBootstrap()
    }

    var selectedTask: WorkTask? {
        guard let selectedTaskID else { return nil }
        return tasks.first(where: { $0.id == selectedTaskID })
    }

    var selectedStrategy: StrategyProfile {
        if let selectedStrategyID,
           let strategy = strategyProfiles.first(where: { $0.id == selectedStrategyID })
        {
            return strategy
        }

        if let fallback = strategyProfiles.first {
            return fallback
        }

        return StrategyProfile(
            name: "均衡默认",
            mode: .balanced,
            maxParallelAgents: 3,
            autoAdvance: true,
            summary: "默认均衡策略"
        )
    }

    func setExecutionMode(_ mode: ExecutionMode) {
        executionMode = mode
        globalMessage = "执行模式已切换为：\(mode.title)"
        persistSnapshot()
    }

    func createTask() {
        let task = WorkTask(
            title: "新任务 \(tasks.count + 1)",
            goal: "将需求拆解为可验证阶段，并交付可运行成果。",
            constraints: [
                "遵循仓库规范与 AGENTS.md 约束",
                "每个阶段产出可验证证据",
            ],
            acceptanceCriteria: [
                "至少一个代理会话完成实现",
                "测试与检查结果回填任务卡",
                "形成可复盘摘要",
            ],
            riskNotes: [
                "并行代理输出冲突",
                "配额或时长接近上限",
            ]
        )

        tasks.insert(task, at: 0)
        selectedTaskID = task.id
        globalMessage = "已创建任务：\(task.title)"
        persistSnapshot()
    }

    func duplicateTask(_ taskID: UUID) {
        guard let original = tasks.first(where: { $0.id == taskID }) else { return }
        var duplicated = original
        duplicated = WorkTask(
            title: "\(original.title)（副本）",
            goal: original.goal,
            constraints: original.constraints,
            acceptanceCriteria: original.acceptanceCriteria,
            riskNotes: original.riskNotes,
            governancePolicy: original.governancePolicy
        )

        tasks.insert(duplicated, at: 0)
        selectedTaskID = duplicated.id
        globalMessage = "已创建副本任务"
        persistSnapshot()
    }

    func deleteTask(_ taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
        if selectedTaskID == taskID {
            selectedTaskID = tasks.first?.id
        }
        globalMessage = "任务已删除"
        persistSnapshot()
    }

    func setStrategy(_ strategyID: UUID) {
        selectedStrategyID = strategyID
        globalMessage = "已切换策略：\(selectedStrategy.name)"
        persistSnapshot()
    }

    func updateCommandTemplate(agent: AgentKind, command: String) {
        commandTemplates[agent] = command
        globalMessage = "已更新 \(agent.displayName) 命令模板"
        persistSnapshot()
    }

    func startSelectedTask() {
        guard let taskID = selectedTaskID else { return }
        startTask(taskID)
    }

    func startTask(_ taskID: UUID) {
        guard let index = indexOfTask(taskID) else { return }

        var task = tasks[index]
        let strategy = selectedStrategy

        if task.status == .inProgress {
            globalMessage = "任务正在执行中"
            return
        }

        task.status = .inProgress
        task.governancePolicy = GovernancePolicy.defaults(for: strategy.mode)
        task.approval.requiredApprovals = task.governancePolicy.requiredApprovals
        task.approval.fallbackAction = task.governancePolicy.fallbackAction
        task.approval.timeoutAt = nil
        task.approval.grantedApprovals = []
        task.approval.isResolved = false
        task.updatedAt = Date()

        if task.phase == .plan, lifecycleEngine.canAdvance(task) {
            _ = lifecycleEngine.advance(&task)
        }

        let selectedAgents = Array(AgentKind.allCases.prefix(max(1, strategy.maxParallelAgents)))

        for agent in selectedAgents {
            let sessionID = UUID()
            let command = commandTemplates[agent] ?? agent.defaultCommand
            let session = AgentSession(
                id: sessionID,
                agent: agent,
                command: command,
                state: .running,
                latestMessage: "已启动"
            )

            task.sessions.append(session)

            Task {
                await activeProvider().start(sessionID: sessionID, command: command)
            }
        }

        appendRecoveryPoint(to: &task, note: "开始执行，策略：\(strategy.name)")
        updateBudgetAfterTaskStart(&task, strategy: strategy)
        tasks[index] = task

        globalMessage = "任务执行已启动（\(selectedAgents.count) 个代理）"
        persistSnapshot()
    }

    func pauseSelectedTask() {
        guard let taskID = selectedTaskID else { return }
        pauseTask(taskID)
    }

    func pauseTask(_ taskID: UUID) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]

        for session in task.sessions where session.state == .running || session.state == .waitingApproval {
            Task {
                await activeProvider().stop(sessionID: session.id)
            }
        }

        for i in task.sessions.indices {
            if task.sessions[i].state == .running || task.sessions[i].state == .waitingApproval {
                task.sessions[i].state = .cancelled
                task.sessions[i].failureCategory = .cancelled
                task.sessions[i].recommendedRecovery = .retry
                task.sessions[i].finishedAt = Date()
                task.sessions[i].latestMessage = "已暂停"
            }
        }

        task.status = .paused
        task.updatedAt = Date()
        appendRecoveryPoint(to: &task, note: "手动暂停任务")
        tasks[index] = task
        globalMessage = "任务已暂停"
        persistSnapshot()
    }

    func resumeSelectedTask() {
        guard let taskID = selectedTaskID else { return }
        resumeTask(taskID)
    }

    func resumeTask(_ taskID: UUID) {
        guard let index = indexOfTask(taskID) else { return }

        var task = tasks[index]
        task.status = .ready
        task.updatedAt = Date()
        appendRecoveryPoint(to: &task, note: "从恢复点继续执行")
        tasks[index] = task
        globalMessage = "任务已恢复，正在重新启动代理"

        startTask(taskID)
    }

    func advanceSelectedTaskPhase() {
        guard let taskID = selectedTaskID else { return }
        guard let index = indexOfTask(taskID) else { return }

        var task = tasks[index]
        let advanced = lifecycleEngine.advance(&task)

        if !advanced {
            globalMessage = "当前阶段未满足推进条件"
        } else {
            globalMessage = "已推进到阶段：\(task.phase.title)"
        }

        tasks[index] = task
        persistSnapshot()
    }

    func setValidation(
        taskID: UUID,
        testsPassed: Bool? = nil,
        lintPassed: Bool? = nil,
        reviewPassed: Bool? = nil,
        acceptancePassed: Bool? = nil,
        hasConflict: Bool? = nil
    ) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]

        if let testsPassed { task.validation.testsPassed = testsPassed }
        if let lintPassed { task.validation.lintPassed = lintPassed }
        if let reviewPassed { task.validation.reviewPassed = reviewPassed }
        if let acceptancePassed { task.validation.acceptancePassed = acceptancePassed }
        if let hasConflict {
            lifecycleEngine.withConflictDecision(&task, hasConflict: hasConflict)
        }

        if task.status == .needsDecision && !task.validation.hasConflict {
            task.status = .inProgress
        }

        autoAdvanceIfNeeded(&task)
        task.updatedAt = Date()
        tasks[index] = task
        persistSnapshot()
    }

    func resolveConflict(taskID: UUID) {
        setValidation(taskID: taskID, hasConflict: false)
        globalMessage = "冲突已标记为已处理"
    }

    func resolveApproval(taskID: UUID, sessionID: UUID, approve: Bool, role: ApprovalRole = .owner) {
        guard let index = indexOfTask(taskID) else { return }
        guard let sessionIndex = tasks[index].sessions.firstIndex(where: { $0.id == sessionID }) else { return }

        var task = tasks[index]
        guard task.sessions[sessionIndex].state == .waitingApproval || task.sessions[sessionIndex].state == .blocked else { return }

        evaluateApprovalTimeout(task: &task)

        if approve {
            if !task.approval.grantedApprovals.contains(role) {
                task.approval.grantedApprovals.append(role)
            }

            let reachedQuorum = task.approval.grantedApprovals.count >= task.approval.requiredApprovals
            if reachedQuorum {
                for i in task.sessions.indices where task.sessions[i].state == .waitingApproval || task.sessions[i].state == .blocked {
                    task.sessions[i].state = .running
                    task.sessions[i].latestMessage = "审批通过，继续执行"
                }
                task.approval.isResolved = true
                task.approval.timeoutAt = nil
                if !task.validation.hasConflict && task.status != .failed {
                    task.status = .inProgress
                }
                globalMessage = "已达到审批 quorum（\(task.approval.grantedApprovals.count)/\(task.approval.requiredApprovals)）"
            } else {
                task.sessions[sessionIndex].state = .waitingApproval
                task.sessions[sessionIndex].latestMessage = "已收集审批（\(task.approval.grantedApprovals.count)/\(task.approval.requiredApprovals)）"
                task.status = .needsDecision
                globalMessage = "审批已记录，等待更多批准"
            }
        } else {
            task.sessions[sessionIndex].state = .blocked
            task.sessions[sessionIndex].latestMessage = "审批拒绝，等待处理"
            task.status = .needsDecision
            task.approval.isResolved = true
            globalMessage = "审批已拒绝，会话进入阻塞"
        }

        task.updatedAt = Date()
        appendRecoveryPoint(
            to: &task,
            note: approve ? "人工审批：\(role.title) 通过" : "人工审批：\(role.title) 拒绝"
        )
        tasks[index] = task
        persistSnapshot()
    }

    func evaluateApprovalTimeout(taskID: UUID) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]
        evaluateApprovalTimeout(task: &task)
        tasks[index] = task
        persistSnapshot()
    }

    func approvalRemainingSeconds(taskID: UUID) -> Int? {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        guard let timeoutAt = task.approval.timeoutAt else { return nil }
        let remaining = Int(timeoutAt.timeIntervalSinceNow.rounded(.up))
        return max(0, remaining)
    }

    func retrySession(taskID: UUID, sessionID: UUID) {
        guard let index = indexOfTask(taskID) else { return }
        guard let sourceIndex = tasks[index].sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let sourceSession = tasks[index].sessions[sourceIndex]
        guard sourceSession.state == .failed || sourceSession.state == .blocked || sourceSession.state == .cancelled else { return }

        var task = tasks[index]
        task.sessions[sourceIndex].recoveredAt = Date()

        let retriedSession = AgentSession(
            agent: sourceSession.agent,
            command: sourceSession.command,
            state: .running,
            latestMessage: "重试中"
        )
        task.sessions.append(retriedSession)
        task.status = .inProgress
        task.updatedAt = Date()
        appendRecoveryPoint(to: &task, note: "重试会话：\(sourceSession.agent.displayName)")
        tasks[index] = task
        globalMessage = "已重试会话：\(sourceSession.agent.displayName)"

        Task {
            await activeProvider().start(sessionID: retriedSession.id, command: retriedSession.command)
        }
        persistSnapshot()
    }

    func restoreTask(taskID: UUID, recoveryPointID: UUID) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]
        guard let recoveryPoint = task.recoveryPoints.first(where: { $0.id == recoveryPointID }) else { return }
        guard let checkpoint = recoveryPoint.checkpoint else {
            globalMessage = "该恢复点来自旧版本，缺少可回滚快照"
            return
        }

        task.phase = checkpoint.phase
        task.phaseHistory = checkpoint.phaseHistory
        task.validation = checkpoint.validation
        task.budget = checkpoint.budget
        task.approval = checkpoint.approval
        task.summary = checkpoint.summary
        task.sessions = checkpoint.sessions.map { session in
            var mutableSession = session
            if mutableSession.state == .running || mutableSession.state == .waitingApproval {
                mutableSession.state = .blocked
                mutableSession.latestMessage = "已从恢复点载入，需手动重启会话"
                mutableSession.finishedAt = Date()
                mutableSession.failureCategory = .unknown
                mutableSession.recommendedRecovery = .retry
            }
            return mutableSession
        }
        task.status = checkpoint.status == .inProgress ? .paused : checkpoint.status
        task.updatedAt = Date()
        appendRecoveryPoint(to: &task, note: "已恢复到：\(recoveryPoint.note)")
        tasks[index] = task
        globalMessage = "任务已恢复到指定恢复点"
        persistSnapshot()
    }

    func generateSummary(taskID: UUID) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]
        task.summary = buildSummary(for: task)
        task.updatedAt = Date()
        appendRecoveryPoint(to: &task, note: "生成任务总结")
        tasks[index] = task
        globalMessage = "任务总结已更新"
        persistSnapshot()
    }

    @discardableResult
    func exportDeliveryReport(taskID: UUID) -> DeliveryReportOutput? {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        let report = DeliveryReport(
            taskID: task.id,
            title: task.title,
            generatedAt: Date(),
            executionMode: executionMode,
            phase: task.phase,
            status: task.status,
            metrics: metricsFromTask(task),
            warnings: budgetGuard.warnings(for: task),
            summary: task.summary.isEmpty ? buildSummary(for: task) : task.summary
        )

        do {
            let output = try reportExporter.export(report: report)
            globalMessage = "报告已导出：\(output.markdownURL.lastPathComponent)"
            return output
        } catch {
            globalMessage = "报告导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func metrics(for taskID: UUID) -> DeliveryMetrics {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return .zero }

        let recoveryDurations = task.sessions.compactMap { session -> Int? in
            guard let finishedAt = session.finishedAt,
                  let recoveredAt = session.recoveredAt,
                  recoveredAt >= finishedAt
            else {
                return nil
            }
            return Int(recoveredAt.timeIntervalSince(finishedAt))
        }
        let avgRecovery = recoveryDurations.isEmpty ? 0 : recoveryDurations.reduce(0, +) / recoveryDurations.count

        let maxRatio = max(task.budget.tokenUsageRatio, task.budget.costUsageRatio, task.budget.runtimeUsageRatio)
        let budgetDeviation = max(0, Int(((maxRatio - 1) * 100).rounded()))

        let checks = [task.validation.testsPassed, task.validation.lintPassed, task.validation.reviewPassed, task.validation.acceptancePassed]
        let passCount = checks.filter { $0 }.count
        let passRate = Int((Double(passCount) / Double(checks.count) * 100).rounded())

        return DeliveryMetrics(
            recoveryAverageSeconds: avgRecovery,
            budgetDeviationPercent: budgetDeviation,
            validationPassRatePercent: passRate
        )
    }

    func budgetWarnings(for taskID: UUID) -> [String] {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return [] }
        return budgetGuard.warnings(for: task)
    }

    func combinedLog(for taskID: UUID) -> String {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return "" }

        let lines = task.sessions.flatMap { session in
            session.output.map { "[\(session.agent.displayName)] \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    func updateTaskMeta(
        taskID: UUID,
        title: String,
        goal: String,
        constraints: [String],
        acceptanceCriteria: [String],
        riskNotes: [String]
    ) {
        guard let index = indexOfTask(taskID) else { return }
        var task = tasks[index]
        task.title = title
        task.goal = goal
        task.constraints = constraints
        task.acceptanceCriteria = acceptanceCriteria
        task.riskNotes = riskNotes
        task.updatedAt = Date()
        tasks[index] = task
        persistSnapshot()
    }

    private func handleExecutionEvent(_ event: AgentExecutionEvent) {
        switch event {
        case let .started(sessionID):
            mutateSession(sessionID: sessionID) { session in
                session.state = .running
                session.latestMessage = "执行中"
                session.startedAt = Date()
            }
        case let .output(sessionID, line):
            mutateSession(sessionID: sessionID) { session in
                session.output.append(line)
                session.latestMessage = line
                session.estimatedTokens += max(8, line.count / 4)
                session.estimatedCost += Double(max(1, line.count / 30)) * 0.001
            }
        case let .waitingApproval(sessionID, line):
            mutateSession(sessionID: sessionID) { session in
                session.output.append(line)
                session.latestMessage = line
                session.state = .waitingApproval
            }
            mutateTaskForSession(sessionID: sessionID) { task in
                if task.status != .needsDecision {
                    appendRecoveryPoint(to: &task, note: "出现授权决策门")
                }
                task.approval.requiredApprovals = task.governancePolicy.requiredApprovals
                task.approval.fallbackAction = task.governancePolicy.fallbackAction
                if task.approval.timeoutAt == nil {
                    task.approval.timeoutAt = Date().addingTimeInterval(TimeInterval(task.governancePolicy.timeoutSeconds))
                }
                task.status = .needsDecision
                task.updatedAt = Date()
            }
        case let .finished(sessionID, exitCode):
            mutateSession(sessionID: sessionID) { session in
                session.state = exitCode == 0 ? .completed : .failed
                session.failureCategory = exitCode == 0 ? nil : .runtimeError
                session.recommendedRecovery = exitCode == 0 ? nil : .retry
                session.finishedAt = Date()
                session.latestMessage = exitCode == 0 ? "执行完成" : "退出码 \(exitCode)"
            }
            mutateTaskForSession(sessionID: sessionID) { task in
                if exitCode == 0 {
                    if task.sessions.allSatisfy({ $0.state != .running && $0.state != .waitingApproval }) {
                        task.status = .inProgress
                        autoAdvanceIfNeeded(&task)
                    }
                } else {
                    task.status = .failed
                }
                task.updatedAt = Date()
                appendRecoveryPoint(to: &task, note: "会话结束，退出码 \(exitCode)")
            }
        case let .failed(sessionID, message):
            mutateSession(sessionID: sessionID) { session in
                session.state = .failed
                session.failureCategory = classifyFailure(message: message)
                session.recommendedRecovery = recommendedRecovery(for: session.failureCategory)
                session.finishedAt = Date()
                session.output.append("ERROR: \(message)")
                session.latestMessage = "执行失败"
            }
            mutateTaskForSession(sessionID: sessionID) { task in
                task.status = .failed
                task.updatedAt = Date()
                appendRecoveryPoint(to: &task, note: "会话异常：\(message)")
            }
        case let .cancelled(sessionID):
            mutateSession(sessionID: sessionID) { session in
                session.state = .cancelled
                session.failureCategory = .cancelled
                session.recommendedRecovery = .retry
                session.finishedAt = Date()
                session.latestMessage = "已取消"
            }
        }

        recalculateBudgets()
        persistSnapshot()
    }

    private func mutateSession(sessionID: UUID, mutation: (inout AgentSession) -> Void) {
        for taskIndex in tasks.indices {
            if let sessionIndex = tasks[taskIndex].sessions.firstIndex(where: { $0.id == sessionID }) {
                mutation(&tasks[taskIndex].sessions[sessionIndex])
                tasks[taskIndex].updatedAt = Date()
                return
            }
        }
    }

    private func mutateTaskForSession(sessionID: UUID, mutation: (inout WorkTask) -> Void) {
        for taskIndex in tasks.indices where tasks[taskIndex].sessions.contains(where: { $0.id == sessionID }) {
            mutation(&tasks[taskIndex])
            return
        }
    }

    private func recalculateBudgets() {
        for index in tasks.indices {
            var tokenTotal = 0
            var costTotal: Double = 0
            let runningCount = tasks[index].sessions.filter { $0.state == .running || $0.state == .waitingApproval }.count

            for session in tasks[index].sessions {
                tokenTotal += session.estimatedTokens
                costTotal += session.estimatedCost
            }

            tasks[index].budget.tokenUsed = tokenTotal
            tasks[index].budget.costUsed = costTotal
            tasks[index].budget.runtimeSeconds += runningCount
            tasks[index].updatedAt = Date()
        }
    }

    private func updateBudgetAfterTaskStart(_ task: inout WorkTask, strategy: StrategyProfile) {
        budgetGuard.applyStrategyTemplate(mode: strategy.mode, budget: &task.budget, policy: task.governancePolicy)
    }

    private func appendRecoveryPoint(to task: inout WorkTask, note: String) {
        let checkpoint = TaskCheckpoint(
            phase: task.phase,
            phaseHistory: task.phaseHistory,
            status: task.status,
            sessions: task.sessions,
            budget: task.budget,
            validation: task.validation,
            approval: task.approval,
            summary: task.summary
        )
        task.recoveryPoints.append(RecoveryPoint(note: note, checkpoint: checkpoint))
        if task.recoveryPoints.count > 80 {
            task.recoveryPoints.removeFirst(task.recoveryPoints.count - 80)
        }
    }

    private func autoAdvanceIfNeeded(_ task: inout WorkTask) {
        guard selectedStrategy.autoAdvance else { return }
        guard task.status != .paused else { return }
        guard task.status != .failed else { return }
        guard task.status != .needsDecision else { return }
        guard task.status == .inProgress || task.status == .completed else { return }

        var lastPhase = task.phase
        var advanced = false

        while lifecycleEngine.canAdvance(task) {
            guard lifecycleEngine.advance(&task) else { break }
            advanced = true
            if task.status == .completed {
                break
            }
            if task.phase == lastPhase {
                break
            }
            lastPhase = task.phase
        }

        if advanced {
            if task.status == .completed {
                task.summary = buildSummary(for: task)
                globalMessage = "任务已自动完成验收"
            } else {
                globalMessage = "任务已自动推进到阶段：\(task.phase.title)"
            }
        }
    }

    private func evaluateApprovalTimeout(task: inout WorkTask) {
        guard let timeoutAt = task.approval.timeoutAt else { return }
        guard timeoutAt <= Date() else { return }
        guard task.sessions.contains(where: { $0.state == .waitingApproval || $0.state == .blocked }) else { return }

        switch task.approval.fallbackAction {
        case .autoApprove:
            for i in task.sessions.indices where task.sessions[i].state == .waitingApproval || task.sessions[i].state == .blocked {
                task.sessions[i].state = .running
                task.sessions[i].latestMessage = "审批超时，系统自动放行"
            }
            task.status = .inProgress
            globalMessage = "审批超时，已按策略自动放行"
        case .autoBlock:
            for i in task.sessions.indices where task.sessions[i].state == .waitingApproval {
                task.sessions[i].state = .blocked
                task.sessions[i].latestMessage = "审批超时，系统自动阻塞"
            }
            task.status = .needsDecision
            globalMessage = "审批超时，已按策略自动阻塞"
        }

        task.approval.isResolved = true
        task.approval.timeoutAt = nil
        appendRecoveryPoint(to: &task, note: "审批超时触发 fallback：\(task.approval.fallbackAction.title)")
    }

    private func classifyFailure(message: String) -> FailureCategory {
        let lower = message.lowercased()
        if lower.contains("permission") || lower.contains("denied") {
            return .permissionDenied
        }
        if lower.contains("timeout") {
            return .timeout
        }
        return .runtimeError
    }

    private func recommendedRecovery(for category: FailureCategory?) -> RecoveryAction {
        switch category {
        case .permissionDenied:
            return .manualInspection
        case .timeout:
            return .rollback
        case .runtimeError:
            return .retry
        case .cancelled:
            return .retry
        case .unknown, .none:
            return .manualInspection
        }
    }

    private func buildSummary(for task: WorkTask) -> String {
        let successCount = task.sessions.filter { $0.state == .completed }.count
        let failedCount = task.sessions.filter { $0.state == .failed }.count
        let blockedCount = task.sessions.filter { $0.state == .blocked || $0.state == .waitingApproval }.count
        let warnings = budgetGuard.warnings(for: task)
        let metrics = metricsFromTask(task)

        let nextStep: String
        if task.status == .completed {
            nextStep = "进入复盘与资产沉淀，准备下一个任务。"
        } else if blockedCount > 0 || task.status == .needsDecision {
            nextStep = "优先清理决策门与阻塞会话，再继续推进。"
        } else if failedCount > 0 {
            nextStep = "重试失败会话并检查命令模板与约束。"
        } else {
            nextStep = "继续执行并补齐阶段门验证。"
        }

        return """
        任务：\(task.title)
        当前阶段：\(task.phase.title)（状态：\(statusTitle(task.status))）
        会话统计：成功 \(successCount) / 失败 \(failedCount) / 决策或阻塞 \(blockedCount) / 总计 \(task.sessions.count)
        预算：Token \(task.budget.tokenUsed)/\(task.budget.tokenLimit)，成本 $\(task.budget.costUsed.formatted(.number.precision(.fractionLength(2))))/$\(task.budget.costLimit.formatted(.number.precision(.fractionLength(2))))
        指标：恢复均时 \(metrics.recoveryAverageSeconds)s，预算偏差 \(metrics.budgetDeviationPercent)%，阶段门通过率 \(metrics.validationPassRatePercent)%
        风险告警：\(warnings.isEmpty ? "无" : warnings.joined(separator: "；"))
        下一步：\(nextStep)
        """
    }

    private func metricsFromTask(_ task: WorkTask) -> DeliveryMetrics {
        let recoveryDurations = task.sessions.compactMap { session -> Int? in
            guard let finishedAt = session.finishedAt,
                  let recoveredAt = session.recoveredAt,
                  recoveredAt >= finishedAt
            else {
                return nil
            }
            return Int(recoveredAt.timeIntervalSince(finishedAt))
        }

        let avgRecovery = recoveryDurations.isEmpty ? 0 : recoveryDurations.reduce(0, +) / recoveryDurations.count
        let maxRatio = max(task.budget.tokenUsageRatio, task.budget.costUsageRatio, task.budget.runtimeUsageRatio)
        let budgetDeviation = max(0, Int(((maxRatio - 1) * 100).rounded()))
        let checks = [task.validation.testsPassed, task.validation.lintPassed, task.validation.reviewPassed, task.validation.acceptancePassed]
        let passCount = checks.filter { $0 }.count
        let passRate = Int((Double(passCount) / Double(checks.count) * 100).rounded())

        return DeliveryMetrics(
            recoveryAverageSeconds: avgRecovery,
            budgetDeviationPercent: budgetDeviation,
            validationPassRatePercent: passRate
        )
    }

    private func statusTitle(_ status: TaskStatus) -> String {
        switch status {
        case .ready: return "待开始"
        case .inProgress: return "进行中"
        case .paused: return "已暂停"
        case .needsDecision: return "待决策"
        case .failed: return "失败"
        case .completed: return "已完成"
        }
    }

    private func restoreOrBootstrap() {
        if let restored = recoveryCoordinator.restore() {
            tasks = restored.tasks
            strategyProfiles = restored.strategyProfiles.isEmpty ? StrategyProfile.presets : restored.strategyProfiles
            selectedStrategyID = restored.selectedStrategyID ?? strategyProfiles.first?.id
            commandTemplates = AgentKind.allCases.reduce(into: [:]) { partialResult, kind in
                partialResult[kind] = restored.commandTemplates[kind.rawValue] ?? kind.defaultCommand
            }
            executionMode = restored.executionMode ?? .localShell
            selectedTaskID = tasks.first?.id
            globalMessage = "已从恢复快照加载 \(tasks.count) 个任务"
            return
        }

        strategyProfiles = StrategyProfile.presets
        selectedStrategyID = strategyProfiles.first?.id
        tasks = [
            WorkTask(
                title: "Agent OS 初始化任务",
                goal: "建立多代理协同中枢与可恢复任务闭环。",
                constraints: [
                    "统一状态机：运行/授权/阻塞/失败/完成",
                    "关键阶段必须可人工决策",
                ],
                acceptanceCriteria: [
                    "至少 2 个代理并行运行",
                    "阶段推进可追踪",
                    "可恢复点可回放",
                ],
                riskNotes: [
                    "并发日志量可能较大",
                    "预算阈值需及时告警",
                ]
            )
        ]
        selectedTaskID = tasks.first?.id
        globalMessage = "已创建默认工作区"
        persistSnapshot()
    }

    private func indexOfTask(_ taskID: UUID) -> Int? {
        tasks.firstIndex(where: { $0.id == taskID })
    }

    private func activeProvider() -> any ExecutionProvider {
        switch executionMode {
        case .localShell:
            return localExecutionProvider
        case .scenario:
            return scenarioExecutionProvider
        }
    }

    private func persistSnapshot() {
        let snapshot = WorkspaceSnapshot(
            tasks: tasks,
            strategyProfiles: strategyProfiles,
            selectedStrategyID: selectedStrategyID,
            commandTemplates: commandTemplates.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            executionMode: executionMode,
            updatedAt: Date()
        )

        recoveryCoordinator.persist(snapshot)
    }
}
