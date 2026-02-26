import AppKit
import Darwin
import Foundation
import Observation

private struct PersistedTerminalWorkspaceSnapshot: Codable {
    var schemaVersion: Int
    var workspacePath: String
    var recentDirectories: [String]
    var favoriteDirectories: [String]
    var recentlyClosedSessions: [PersistedClosedTerminalSessionSnapshot]?
    var sessionOrder: [UUID]?
    var selectedSessionID: UUID?
    var sessions: [PersistedTerminalSessionSnapshot]

    static let currentSchemaVersion = 1
}

private struct PersistedTerminalSessionSnapshot: Codable {
    let id: UUID
    let tool: String
    let title: String
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date
    let endedAt: Date?
    let exitCode: Int32?
    let lastInput: String?
    let outputPreview: String
    let transcriptFilePath: String?
    let codexConversationID: String?
}

private struct PersistedClosedTerminalSessionSnapshot: Codable {
    let id: UUID
    let tool: String
    let title: String
    let workingDirectory: String
    let closedAt: Date
}

struct ClosedTerminalSessionRecord: Identifiable, Equatable {
    let id: UUID
    let tool: ProgrammingTool
    let title: String
    let workingDirectory: String
    let closedAt: Date
}

private struct TerminalRuntimeLaunchCommand {
    let executable: String
    let arguments: [String]
    let usesNodeWrapper: Bool
}

@MainActor
@Observable
final class AppState {
    private let detectionService: CLIDetectionService
    let installationService: ToolInstallationService
    let configEditorService: ConfigEditorService
    private let terminalRunnerFactory: () -> any CLITerminalRunning
    private let codexConversationBootstrapperFactory: () -> any CodexConversationBootstrapping
    private let codexAppServerMonitorFactory: (CodexAppServerMonitor.Configuration) -> any CodexAppServerMonitoring
    private let terminalNotificationService: TerminalNotificationServiceProtocol

    private var terminalRunners: [UUID: any CLITerminalRunning] = [:]
    private var terminalLastResize: [UUID: (cols: Int, rows: Int)] = [:]
    private var terminalRuntimeStates: [UUID: TerminalSessionRuntimeState] = [:]
    private var terminalRuntimeStateSources: [UUID: TerminalRuntimeSignalSource] = [:]
    private var terminalIPCServers: [UUID: any AgentRuntimeIPCServing] = [:]
    private var terminalIPCSocketPaths: [UUID: String] = [:]
    private var terminalPendingApprovals: [UUID: TerminalApprovalRequest] = [:]
    private var codexAppServerMonitors: [UUID: any CodexAppServerMonitoring] = [:]
    private let maxTerminalOutputCharacters = 4_096
    private let maxTerminalOutputBytes = 1_200_000
    private let userDefaults: UserDefaults
    private let terminalWorkspaceSnapshotStorageKey: String
    private let isTerminalWorkspacePersistenceEnabled: Bool
    private let maxRecentWorkspaceDirectories = 20
    private let maxFavoriteWorkspaceDirectories = 20
    private let maxPersistedTerminalSessions = 40
    private let maxRecentlyClosedTerminalSessions = 20
    private let maxRecentQuickLaunchCommands = 8
    private let isNodeWrapperRuntimeEnabled: Bool
    // Rollback: keep Codex in classic terminal mode by default.
    // Protocol-driven mode can be re-enabled later after stability validation.
    private let isCodexProtocolModeEnabled = false

    var installations: [ToolInstallation] = []
    var selectedToolForConfig: ProgrammingTool?
    var configOperationStatus = ""
    var updateCheckResults: [ProgrammingTool: ToolUpdateCheckResult] = [:]
    var checkingUpdateTools: Set<ProgrammingTool> = []
    var updatingTools: Set<ProgrammingTool> = []
    var installingTools: Set<ProgrammingTool> = []
    var repairingNpmCacheTools: Set<ProgrammingTool> = []
    var operationLogs: [ProgrammingTool: [String]] = [:]

    var terminalSessions: [CLITerminalSession] = []
    var terminalSessionOrder: [UUID] = []
    var selectedTerminalSessionID: UUID?
    var recentWorkspaceDirectories: [String] = []
    var favoriteWorkspaceDirectories: [String] = []
    var recentlyClosedTerminalSessions: [ClosedTerminalSessionRecord] = []
    var recentQuickLaunchCommands: [String] = []

    var workspacePath: String = ""
    var selectedAgent: AgentKind = .codex {
        didSet {
            if !selectedAgent.models.contains(selectedModel), let first = selectedAgent.models.first {
                selectedModel = first
            }
        }
    }
    var selectedModel: String = "gpt-5-codex"
    var runMode: RunMode = .local

    var step: SessionStep = .draft
    var sessionTitle: String = "新会话"
    var objective: String = "先明确目标，再执行、审批、交付。"

    var showingInspector: Bool = false
    var liveOutput: String = ""
    var detectionStatuses: [ToolDetectionStatus] = []
    var detectionUpdatedAt: Date?
    var events: [SessionEvent] = [
        SessionEvent(actor: "System", message: "创建新会话。")
    ]

    var installedToolCount: Int {
        installations.filter(\.isInstalled).count
    }

    var uninstalledToolCount: Int {
        max(installations.count - installedToolCount, 0)
    }

    init(
        detectionService: CLIDetectionService = CLIDetectionService(),
        installationService: ToolInstallationService = ToolInstallationService(),
        configEditorService: ConfigEditorService = ConfigEditorService(),
        terminalRunnerFactory: @escaping () -> any CLITerminalRunning = { CLITerminalRunnerFactory.makeDefaultRunner() },
        codexConversationBootstrapperFactory: @escaping () -> any CodexConversationBootstrapping = {
            CodexConversationBootstrapper()
        },
        codexAppServerMonitorFactory: @escaping (CodexAppServerMonitor.Configuration) -> any CodexAppServerMonitoring = {
            CodexAppServerMonitor(configuration: $0)
        },
        terminalNotificationService: TerminalNotificationServiceProtocol = NoopTerminalNotificationService(),
        terminalOutputFlushDelayNanos: UInt64 = 16_000_000,
        userDefaults: UserDefaults = .standard,
        terminalWorkspaceSnapshotStorageKey: String = "agentos.terminal.workspace.snapshot.v1",
        isTerminalWorkspacePersistenceEnabled: Bool = false,
        isNodeWrapperRuntimeEnabled: Bool = ProcessInfo.processInfo.environment["AGENTOS_ENABLE_NODE_WRAPPER"] != "0"
    ) {
        self.detectionService = detectionService
        self.installationService = installationService
        self.configEditorService = configEditorService
        self.terminalRunnerFactory = terminalRunnerFactory
        self.codexConversationBootstrapperFactory = codexConversationBootstrapperFactory
        self.codexAppServerMonitorFactory = codexAppServerMonitorFactory
        self.terminalNotificationService = terminalNotificationService
        _ = terminalOutputFlushDelayNanos
        self.userDefaults = userDefaults
        self.terminalWorkspaceSnapshotStorageKey = terminalWorkspaceSnapshotStorageKey
        self.isTerminalWorkspacePersistenceEnabled = isTerminalWorkspacePersistenceEnabled
        self.isNodeWrapperRuntimeEnabled = isNodeWrapperRuntimeEnabled

        self.terminalNotificationService.requestAuthorizationIfNeeded()
        restoreTerminalWorkspaceSnapshotIfNeeded()
        refreshDetections()
        refreshInstallations()
    }


    func saveWorkspace(path: String) {
        guard let normalizedPath = normalizeDirectoryPath(path) else { return }
        workspacePath = normalizedPath
        rememberWorkspaceDirectory(normalizedPath)
        persistTerminalWorkspaceSnapshotIfNeeded()
        append(actor: "System", message: "工作目录已保存：\(normalizedPath)")
    }

    func preferredTerminalToolForNewSession() -> ProgrammingTool? {
        if let selectedTerminalSessionID,
           let selectedSession = terminalSession(for: selectedTerminalSessionID),
           selectedSession.tool.supportsIntegratedTerminal {
            return selectedSession.tool
        }

        if let latestSession = terminalSessions.first(where: { $0.tool.supportsIntegratedTerminal }) {
            return latestSession.tool
        }

        return installations.first(where: { $0.isInstalled && $0.tool.supportsIntegratedTerminal })?.tool
    }

    func promptWorkspaceDirectoryForNewSession(initialPath: String? = nil) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "选择目录"
        panel.message = "新建终端会话前，请选择该会话的工作目录。"

        if let preferredPath = normalizeDirectoryPath(initialPath ?? "") ?? normalizeDirectoryPath(workspacePath) {
            panel.directoryURL = URL(fileURLWithPath: preferredPath, isDirectory: true)
        }

        if panel.runModal() == .OK, let path = panel.url?.path {
            return path
        }

        configOperationStatus = "已取消目录选择，未新建终端会话。"
        return nil
    }

    @discardableResult
    func createTerminalSessionWithDirectorySelection(
        preferredTool: ProgrammingTool? = nil,
        initialDirectory: String? = nil
    ) -> UUID? {
        guard let tool = preferredTool ?? preferredTerminalToolForNewSession() else {
            configOperationStatus = "请先安装支持终端的 CLI，再新建会话。"
            return nil
        }

        guard let directoryPath = promptWorkspaceDirectoryForNewSession(initialPath: initialDirectory) else {
            return nil
        }

        saveWorkspace(path: directoryPath)
        guard let sessionID = createTerminalSession(for: tool, workingDirectory: directoryPath) else {
            return nil
        }
        selectTerminalSession(sessionID)
        return sessionID
    }

    func isFavoriteWorkspaceDirectory(_ path: String) -> Bool {
        guard let normalized = normalizeDirectoryPath(path) else { return false }
        return favoriteWorkspaceDirectories.contains(normalized)
    }

    func toggleFavoriteWorkspaceDirectory(_ path: String) {
        guard let normalized = normalizeDirectoryPath(path) else { return }

        if let index = favoriteWorkspaceDirectories.firstIndex(of: normalized) {
            favoriteWorkspaceDirectories.remove(at: index)
            configOperationStatus = "已取消收藏目录：\(normalized)"
        } else {
            favoriteWorkspaceDirectories.insert(normalized, at: 0)
            favoriteWorkspaceDirectories = deduplicatedPaths(
                favoriteWorkspaceDirectories,
                limit: maxFavoriteWorkspaceDirectories
            )
            rememberWorkspaceDirectory(normalized)
            configOperationStatus = "已收藏目录：\(normalized)"
        }

        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    func removeWorkspaceDirectoryFromRecent(_ path: String) {
        guard let normalized = normalizeDirectoryPath(path) else { return }
        recentWorkspaceDirectories.removeAll { $0 == normalized }
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    func openWorkspaceDirectoryInFinder(_ path: String) {
        guard let normalized = normalizeDirectoryPath(path) else {
            configOperationStatus = "目录路径无效，无法打开。"
            return
        }

        let url = URL(fileURLWithPath: normalized, isDirectory: true)
        if NSWorkspace.shared.open(url) {
            configOperationStatus = "已打开目录：\(normalized)"
        } else {
            configOperationStatus = "无法打开目录：\(normalized)"
        }
    }

    func start() {
        step = .running
        append(actor: selectedAgent.title, message: "开始执行：\(selectedModel)")
        if liveOutput.isEmpty {
            liveOutput = "[\(selectedAgent.title)] starting..."
        }
    }

    func pause() {
        append(actor: "System", message: "执行已暂停")
    }

    func resume() {
        step = .running
        append(actor: "System", message: "继续执行")
    }

    func requestReview() {
        step = .reviewing
        append(actor: "System", message: "进入审批阶段")
    }

    func approve() {
        step = .done
        append(actor: "Owner", message: "审批通过")
    }

    func reject() {
        step = .running
        append(actor: "Owner", message: "审批拒绝，返回执行")
    }

    func appendOutput(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveOutput = liveOutput.isEmpty ? trimmed : "\(liveOutput)\n\(trimmed)"
        append(actor: selectedAgent.title, message: trimmed)
    }

    func refreshDetections() {
        detectionStatuses = detectionService.detectAll()
        detectionUpdatedAt = Date()
        let installedCount = detectionStatuses.filter(\.isInstalled).count
        append(actor: "System", message: "CLI 检测完成：\(installedCount)/\(detectionStatuses.count) 已安装")
    }

    func refreshInstallations() {
        installations = installationService.detectAll()
        append(actor: "System", message: "工具安装检测完成：\(installedToolCount)/\(installations.count) 已安装")
    }

    func installation(for tool: ProgrammingTool?) -> ToolInstallation? {
        guard let tool else { return nil }
        return installations.first(where: { $0.tool == tool })
    }

    func openConfigEditor(for tool: ProgrammingTool) {
        guard tool.supportsDirectConfigEditing else {
            configOperationStatus = "\(tool.title) 不支持在本应用直接编辑参数，请在官方客户端或官方配置文件中设置。"
            selectedToolForConfig = nil
            return
        }
        if selectedToolForConfig == tool {
            selectedToolForConfig = nil
        }
        selectedToolForConfig = tool
        configOperationStatus = "正在打开 \(tool.title) 设置面板"
    }

    func dismissConfigEditor() {
        selectedToolForConfig = nil
    }

    func openConfigDirectory(for tool: ProgrammingTool) {
        let targetPath = installationService.configDirectoryTargetPath(for: tool) ?? (tool.configPaths.first ?? "未知路径")
        let success = installationService.openConfigDirectory(for: tool)
        if success {
            configOperationStatus = "已打开配置目录：\(targetPath)"
        } else {
            configOperationStatus = "无法打开配置目录：\(targetPath)"
        }
    }

    func openInstallDirectory(for tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool }) else {
            configOperationStatus = "未找到安装信息"
            return
        }
        let success = installationService.openInstallDirectory(for: installation)
        if success {
            configOperationStatus = "已打开安装目录：\(installation.installLocation ?? "未知路径")"
        } else {
            configOperationStatus = "无法打开安装目录：\(installation.installLocation ?? "未知路径")"
        }
    }

    func updateTool(_ tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具"
            return
        }

        let service = installationService
        resetOperationLog(for: tool, title: "开始更新 \(tool.title)")
        updatingTools.insert(tool)
        Task { @MainActor in
            do {
                let output = try await service.updateTool(installation)
                appendOperationOutputLines(for: tool, output)
                let status = statusSummary(from: output, fallback: "更新完成")
                configOperationStatus = status
                appendOperationLog(for: tool, status)
                refreshInstallations()
                refreshDetections()
                updateCheckResults.removeValue(forKey: tool)
            } catch {
                configOperationStatus = "更新失败: \(error.localizedDescription)"
                appendOperationLog(for: tool, configOperationStatus)
            }
            updatingTools.remove(tool)
        }
    }

    func uninstallTool(_ tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具"
            return
        }

        let service = installationService
        resetOperationLog(for: tool, title: "开始卸载 \(tool.title)")
        Task { @MainActor in
            do {
                let output = try await service.uninstallTool(installation)
                appendOperationOutputLines(for: tool, output)
                let status = statusSummary(from: output, fallback: "卸载完成")
                configOperationStatus = status
                appendOperationLog(for: tool, status)
                refreshInstallations()
                refreshDetections()
                updateCheckResults.removeValue(forKey: tool)
            } catch {
                configOperationStatus = "卸载失败: \(error.localizedDescription)"
                appendOperationLog(for: tool, configOperationStatus)
            }
        }
    }

    func checkToolUpdate(_ tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具，无法检查更新"
            return
        }

        let service = installationService
        resetOperationLog(for: tool, title: "开始检查 \(tool.title) 更新")
        checkingUpdateTools.insert(tool)
        Task { @MainActor in
            defer { checkingUpdateTools.remove(tool) }
            do {
                let result = try await service.checkForUpdate(installation)
                updateCheckResults[tool] = result
                configOperationStatus = result.message
                appendOperationLog(for: tool, result.message)
            } catch {
                configOperationStatus = "检查更新失败: \(error.localizedDescription)"
                appendOperationLog(for: tool, configOperationStatus)
            }
        }
    }

    func installTool(_ tool: ProgrammingTool) {
        installTool(tool, using: nil)
    }

    func installTool(_ tool: ProgrammingTool, using installMethod: InstallMethod?) {
        guard let installation = installations.first(where: { $0.tool == tool }) else {
            configOperationStatus = "未找到安装信息"
            return
        }

        guard !installation.isInstalled else {
            configOperationStatus = "该工具已安装"
            return
        }

        if installMethod == .direct {
            guard
                let rawURL = tool.officialInstallURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                !rawURL.isEmpty
            else {
                configOperationStatus = "未配置 \(tool.title) 的官网安装地址"
                return
            }

            let normalizedURL = rawURL.contains("://") ? rawURL : "https://\(rawURL)"
            guard let url = URL(string: normalizedURL) else {
                configOperationStatus = "官网安装地址无效：\(rawURL)"
                return
            }

            if NSWorkspace.shared.open(url) {
                configOperationStatus = "已打开 \(tool.title) 官网安装页：\(normalizedURL)"
            } else {
                configOperationStatus = "无法打开 \(tool.title) 官网安装页：\(normalizedURL)"
            }
            return
        }

        let service = installationService
        let installTitle: String
        if let installMethod {
            installTitle = "开始通过 \(installMethod.title) 安装 \(tool.title)"
        } else {
            installTitle = "开始安装 \(tool.title)"
        }
        resetOperationLog(for: tool, title: installTitle)
        installingTools.insert(tool)
        Task { @MainActor in
            defer { installingTools.remove(tool) }
            do {
                let output = try await service.installTool(tool, using: installMethod)
                appendOperationOutputLines(for: tool, output)
                let status = statusSummary(from: output, fallback: "安装完成")
                configOperationStatus = status
                appendOperationLog(for: tool, status)
                refreshInstallations()
                refreshDetections()
            } catch {
                configOperationStatus = "安装失败: \(error.localizedDescription)"
                appendOperationLog(for: tool, configOperationStatus)
            }
        }
    }

    func repairNpmCachePermissions(for tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具，无法修复 npm 缓存权限"
            return
        }

        guard installation.installMethod == .npm else {
            configOperationStatus = "该工具不是 npm 安装方式，无需执行 npm 缓存修复"
            return
        }

        let service = installationService
        resetOperationLog(for: tool, title: "开始修复 npm 缓存权限")
        repairingNpmCacheTools.insert(tool)
        Task { @MainActor in
            defer { repairingNpmCacheTools.remove(tool) }
            let output = await service.repairNpmCachePermissions()
            appendOperationOutputLines(for: tool, output)
            let summary = statusSummary(from: output, fallback: "npm 缓存权限修复失败")

            if summary.localizedStandardContains("命令执行完成（退出码 0）") {
                appendOperationLog(for: tool, "npm 缓存权限修复完成，正在重新检查更新")
                do {
                    let result = try await service.checkForUpdate(installation)
                    updateCheckResults[tool] = result
                    configOperationStatus = result.message
                    appendOperationLog(for: tool, "复检结果：\(result.message)")
                } catch {
                    configOperationStatus = "修复后复检失败: \(error.localizedDescription)"
                    appendOperationLog(for: tool, configOperationStatus)
                }
            } else {
                configOperationStatus = "npm 缓存权限修复失败，请查看日志"
                appendOperationLog(for: tool, configOperationStatus)
            }
        }
    }

    // MARK: - Batch Operations

    func batchUpdateTools(_ tools: Set<ProgrammingTool>) {
        let eligible = tools.filter { tool in
            installations.contains(where: { $0.tool == tool && $0.isInstalled }) && !updatingTools.contains(tool)
        }
        guard !eligible.isEmpty else {
            configOperationStatus = "没有可更新的工具"
            return
        }
        configOperationStatus = "开始批量更新 \(eligible.count) 个工具"
        for tool in eligible {
            updateTool(tool)
        }
    }

    func batchUninstallTools(_ tools: Set<ProgrammingTool>) {
        let eligible = tools.filter { tool in
            installations.contains(where: { $0.tool == tool && $0.isInstalled })
        }
        guard !eligible.isEmpty else {
            configOperationStatus = "没有可卸载的工具"
            return
        }
        configOperationStatus = "开始批量卸载 \(eligible.count) 个工具"
        for tool in eligible {
            uninstallTool(tool)
        }
    }

    func batchCheckUpdates(_ tools: Set<ProgrammingTool>) {
        let eligible = tools.filter { tool in
            installations.contains(where: { $0.tool == tool && $0.isInstalled }) && !checkingUpdateTools.contains(tool)
        }
        guard !eligible.isEmpty else {
            configOperationStatus = "没有可检查更新的工具"
            return
        }
        configOperationStatus = "开始批量检查 \(eligible.count) 个工具的更新"
        for tool in eligible {
            checkToolUpdate(tool)
        }
    }

    var toolsWithAvailableUpdates: Set<ProgrammingTool> {
        Set(updateCheckResults.filter { $0.value.hasUpdate }.map(\.key))
    }

    var isBatchOperationRunning: Bool {
        !updatingTools.isEmpty || !checkingUpdateTools.isEmpty || !installingTools.isEmpty
    }

    func updateCheckResult(for tool: ProgrammingTool) -> ToolUpdateCheckResult? {
        updateCheckResults[tool]
    }

    func isCheckingUpdate(for tool: ProgrammingTool) -> Bool {
        checkingUpdateTools.contains(tool)
    }

    func isUpdating(for tool: ProgrammingTool) -> Bool {
        updatingTools.contains(tool)
    }

    func isInstalling(for tool: ProgrammingTool) -> Bool {
        installingTools.contains(tool)
    }

    func isRepairingNpmCache(for tool: ProgrammingTool) -> Bool {
        repairingNpmCacheTools.contains(tool)
    }

    func operationLog(for tool: ProgrammingTool) -> [String] {
        operationLogs[tool] ?? []
    }

    func terminalSessions(for tool: ProgrammingTool) -> [CLITerminalSession] {
        terminalSessions
            .filter { $0.tool == tool }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func orderedTerminalSessions() -> [CLITerminalSession] {
        let sessions = terminalSessions
        guard !sessions.isEmpty else { return [] }

        let sessionByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        let availableIDs = Set(sessionByID.keys)

        var ordered: [CLITerminalSession] = []
        var consumedIDs = Set<UUID>()

        for sessionID in terminalSessionOrder where availableIDs.contains(sessionID) {
            guard consumedIDs.insert(sessionID).inserted else { continue }
            if let session = sessionByID[sessionID] {
                ordered.append(session)
            }
        }

        let remainingSessions = sessions
            .filter { !consumedIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }
        ordered.append(contentsOf: remainingSessions)
        return ordered
    }

    func moveTerminalSession(_ sessionID: UUID, toIndex requestedIndex: Int) {
        guard !terminalSessions.isEmpty else { return }
        var order = normalizedTerminalSessionOrder()
        guard let currentIndex = order.firstIndex(of: sessionID) else { return }
        var targetIndex = max(0, min(requestedIndex, order.count - 1))
        guard currentIndex != targetIndex else { return }

        order.remove(at: currentIndex)
        if targetIndex > currentIndex {
            targetIndex -= 1
        }
        order.insert(sessionID, at: targetIndex)

        terminalSessionOrder = order
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    func terminalSession(for sessionID: UUID?) -> CLITerminalSession? {
        guard let sessionID else { return nil }
        return terminalSessions.first(where: { $0.id == sessionID })
    }

    func runtimeState(for session: CLITerminalSession) -> TerminalSessionRuntimeState {
        if let runtimeState = terminalRuntimeStates[session.id] {
            return runtimeState
        }
        if session.isRunning {
            if session.tool == .codex, isCodexProtocolModeEnabled {
                return .syncing
            }
            return .working
        }
        if session.isRestoredSnapshot {
            return .restoredStopped
        }
        if let exitCode = session.exitCode {
            return exitCode == 0 ? .completedSuccess : .completedFailure
        }
        return .stopped
    }

    func terminalRuntimeState(for sessionID: UUID) -> TerminalSessionRuntimeState? {
        guard let session = terminalSession(for: sessionID) else { return nil }
        return runtimeState(for: session)
    }

    func runtimeStateSource(for sessionID: UUID) -> TerminalRuntimeSignalSource? {
        terminalRuntimeStateSources[sessionID]
    }

    func pendingApprovalRequest(for sessionID: UUID) -> TerminalApprovalRequest? {
        terminalPendingApprovals[sessionID]
    }

    func approvePendingTerminalAction(_ sessionID: UUID) {
        resolvePendingTerminalApproval(sessionID, approved: true)
    }

    func rejectPendingTerminalAction(_ sessionID: UUID) {
        resolvePendingTerminalApproval(sessionID, approved: false)
    }

    func selectTerminalSession(_ sessionID: UUID?) {
        selectedTerminalSessionID = sessionID
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    @discardableResult
    func createTerminalSession(for tool: ProgrammingTool, workingDirectory: String? = nil) -> UUID? {
        guard tool.supportsIntegratedTerminal else {
            configOperationStatus = "\(tool.title) 暂未接入内置终端。"
            return nil
        }

        guard let installation = installations.first(where: { $0.tool == tool }) else {
            configOperationStatus = "未找到 \(tool.title) 的安装信息"
            return nil
        }

        guard installation.isInstalled else {
            configOperationStatus = "\(tool.title) 未安装，无法启动内置终端会话"
            return nil
        }

        guard let launch = resolveLaunchCommand(for: installation) else {
            configOperationStatus = "无法解析 \(tool.title) 启动命令"
            return nil
        }

        guard let workspaceDirectory = resolvedWorkspacePath(overridePath: workingDirectory) else {
            configOperationStatus = "请先选择工作目录后再启动终端会话。"
            return nil
        }
        return startTerminalSession(
            tool: tool,
            title: "\(tool.title) 会话",
            executable: launch.executable,
            arguments: launch.arguments,
            workingDirectory: workspaceDirectory
        )
    }

    @discardableResult
    func createTerminalSession(from commandLine: String, workingDirectory: String? = nil) -> UUID? {
        let trimmedCommand = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            configOperationStatus = "请输入要启动的命令。"
            return nil
        }

        guard let tool = resolveProgrammingTool(from: trimmedCommand) else {
            let fallbackToken = firstExecutableToken(in: trimmedCommand) ?? trimmedCommand
            configOperationStatus = "无法识别命令对应的编程 CLI：\(fallbackToken)。请使用受支持的 CLI 命令。"
            return nil
        }

        let workspaceDirectory: String
        if let resolvedWorkspace = resolvedWorkspacePath(overridePath: workingDirectory) {
            workspaceDirectory = resolvedWorkspace
        } else if let selectedDirectory = promptWorkspaceDirectoryForNewSession(initialPath: workingDirectory) {
            workspaceDirectory = selectedDirectory
        } else {
            return nil
        }

        if tool == .codex {
            return createTerminalSession(for: .codex, workingDirectory: workspaceDirectory)
        }

        guard let sessionID = startTerminalSession(
            tool: tool,
            title: "\(tool.title) 会话",
            executable: "/bin/zsh",
            arguments: ["-lc", trimmedCommand],
            workingDirectory: workspaceDirectory,
            statusMessage: "\(tool.title) 会话已启动",
            eventMessage: "已快速启动 \(tool.title) 内置终端会话：\(trimmedCommand)"
        ) else {
            return nil
        }

        rememberQuickLaunchCommand(trimmedCommand)
        return sessionID
    }

    @discardableResult
    func relaunchTerminalSession(_ sessionID: UUID) -> UUID? {
        guard let session = terminalSession(for: sessionID) else {
            configOperationStatus = "会话不存在，无法重启。"
            return nil
        }

        if session.isRunning {
            configOperationStatus = "会话仍在运行，无需重启。"
            return session.id
        }

        return createTerminalSession(for: session.tool, workingDirectory: session.workingDirectory)
    }

    func renameTerminalSession(_ sessionID: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            configOperationStatus = "会话标题不能为空。"
            return
        }

        var didUpdate = false
        mutateTerminalSession(sessionID) { session in
            guard session.title != trimmed else { return }
            session.title = trimmed
            session.updatedAt = Date()
            didUpdate = true
        }
        guard didUpdate else { return }
        configOperationStatus = "会话标题已更新。"
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    @discardableResult
    func duplicateTerminalSession(_ sessionID: UUID) -> UUID? {
        guard let session = terminalSession(for: sessionID) else {
            configOperationStatus = "会话不存在，无法复制。"
            return nil
        }

        guard let duplicatedID = createTerminalSession(
            for: session.tool,
            workingDirectory: session.workingDirectory
        ) else {
            return nil
        }
        renameTerminalSession(duplicatedID, title: "\(session.title) 副本")
        return duplicatedID
    }

    @discardableResult
    func restartTerminalSession(_ sessionID: UUID, workingDirectory: String) -> UUID? {
        guard let session = terminalSession(for: sessionID) else {
            configOperationStatus = "会话不存在，无法重启。"
            return nil
        }

        let normalizedWorkingDirectory = normalizeDirectoryPath(workingDirectory) ?? workingDirectory
        removeTerminalSession(sessionID, rememberClosed: false)
        return createTerminalSession(for: session.tool, workingDirectory: normalizedWorkingDirectory)
    }

    func sendTerminalInput(_ input: String, to sessionID: UUID) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sendTerminalData(Data((trimmed + "\n").utf8), to: sessionID, lastInput: trimmed)
    }

    func sendTerminalControlC(to sessionID: UUID) {
        sendTerminalData(Data([0x03]), to: sessionID, lastInput: "^C")
    }

    func sendTerminalControlL(to sessionID: UUID) {
        sendTerminalData(Data([0x0C]), to: sessionID, lastInput: "^L")
    }

    func terminateTerminalSession(_ sessionID: UUID) {
        guard let runner = terminalRunners[sessionID] else { return }
        runner.terminate()
    }

    func sendTerminalData(_ data: Data, to sessionID: UUID, lastInput: String? = nil) {
        guard let runner = terminalRunners[sessionID] else {
            configOperationStatus = "会话不存在或已结束"
            return
        }
        guard !data.isEmpty else { return }

        runner.send(data: data)
        mutateTerminalSession(sessionID) { session in
            session.lastInput = lastInput
            session.updatedAt = Date()
        }
        applyRuntimeStateIfNeeded(.working, source: .userInput, for: sessionID)
    }

    /// Returns the Ghostty terminal runner for a session.
    /// Used by the view layer to attach the Metal-rendered surface.
    func ghosttyRunner(for sessionID: UUID) -> CLIGhosttyTerminalRunner? {
        terminalRunners[sessionID] as? CLIGhosttyTerminalRunner
    }

    func resizeTerminalSession(_ sessionID: UUID, cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        guard let runner = terminalRunners[sessionID] else { return }
        if let last = terminalLastResize[sessionID], last.cols == cols, last.rows == rows {
            return
        }
        terminalLastResize[sessionID] = (cols: cols, rows: rows)
        runner.resize(cols: cols, rows: rows)
    }

    func clearTerminalSessionBuffer(_ sessionID: UUID) {
        guard let buffer = terminalSession(for: sessionID)?.outputBuffer else {
            configOperationStatus = "会话不存在，无法清空输出。"
            return
        }

        buffer.clear()
        mutateTerminalSession(sessionID) { session in
            session.updatedAt = Date()
        }

        configOperationStatus = "已清空会话输出缓存。"
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    func exportTerminalSessionTranscript(_ sessionID: UUID, to destinationURL: URL) {
        guard let session = terminalSession(for: sessionID) else {
            configOperationStatus = "会话不存在，无法导出对话。"
            return
        }

        let transcript = exportedTranscriptPayload(for: session)
        let metadataLines = [
            "- Tool: \(session.tool.title)",
            "- Command: `\(session.commandLine)`",
            "- Working Directory: `\(session.workingDirectory)`",
            "- Created At: \(session.createdAt.ISO8601Format())",
            "- Updated At: \(session.updatedAt.ISO8601Format())",
            "- Status: \(session.statusText)",
            "- Transcript Source: \(transcript.sourceLabel)",
        ].joined(separator: "\n")

        let fence = markdownCodeFence(for: transcript.text)
        let content = """
        # AgentOS Terminal Session

        \(metadataLines)

        ## Output

        \(fence.opening)
        \(transcript.text)
        \(fence.closing)
        """

        do {
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
            configOperationStatus = "会话对话已导出：\(destinationURL.path)"
        } catch {
            configOperationStatus = "导出失败：\(error.localizedDescription)"
        }
    }

    func updateTerminalSessionWorkingDirectory(_ sessionID: UUID, directory: String?) {
        guard let normalizedDirectory = resolveTerminalReportedDirectory(directory) else { return }

        var didUpdate = false
        mutateTerminalSession(sessionID) { session in
            guard session.workingDirectory != normalizedDirectory else { return }
            session.workingDirectory = normalizedDirectory
            session.updatedAt = Date()
            didUpdate = true
        }

        guard didUpdate else { return }
        rememberWorkspaceDirectory(normalizedDirectory)
        if selectedTerminalSessionID == sessionID {
            workspacePath = normalizedDirectory
        }
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    @discardableResult
    func reopenLastClosedTerminalSession() -> UUID? {
        guard let record = recentlyClosedTerminalSessions.first else {
            configOperationStatus = "没有可恢复的已关闭会话。"
            return nil
        }
        return reopenRecentlyClosedTerminalSession(record.id)
    }

    @discardableResult
    func reopenRecentlyClosedTerminalSession(_ closedSessionID: UUID) -> UUID? {
        guard let record = recentlyClosedTerminalSessions.first(where: { $0.id == closedSessionID }) else {
            configOperationStatus = "关闭会话记录不存在。"
            return nil
        }

        guard let newSessionID = createTerminalSession(for: record.tool, workingDirectory: record.workingDirectory) else {
            return nil
        }

        recentlyClosedTerminalSessions.removeAll { $0.id == record.id }
        persistTerminalWorkspaceSnapshotIfNeeded()
        return newSessionID
    }

    @discardableResult
    func closeCurrentTerminalSession() -> UUID? {
        guard !terminalSessions.isEmpty else {
            configOperationStatus = "当前没有可关闭的会话。"
            return nil
        }

        let targetSessionID: UUID
        if let selectedTerminalSessionID,
           terminalSessions.contains(where: { $0.id == selectedTerminalSessionID }) {
            targetSessionID = selectedTerminalSessionID
        } else if let fallbackSessionID = orderedTerminalSessions().last?.id {
            targetSessionID = fallbackSessionID
        } else {
            configOperationStatus = "当前没有可关闭的会话。"
            return nil
        }

        removeTerminalSession(targetSessionID)
        return targetSessionID
    }

    func clearRecentlyClosedTerminalSessions() {
        recentlyClosedTerminalSessions = []
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    func removeTerminalSession(_ sessionID: UUID, rememberClosed: Bool = true) {
        let sessionToRemove = terminalSession(for: sessionID)

        stopCodexAppServerMonitor(for: sessionID)
        stopRuntimeIPCServer(for: sessionID)
        if let runner = terminalRunners.removeValue(forKey: sessionID) {
            runner.terminate()
        }
        terminalLastResize.removeValue(forKey: sessionID)
        terminalRuntimeStates.removeValue(forKey: sessionID)
        terminalRuntimeStateSources.removeValue(forKey: sessionID)
        terminalPendingApprovals.removeValue(forKey: sessionID)

        terminalSessions.removeAll(where: { $0.id == sessionID })
        terminalSessionOrder.removeAll(where: { $0 == sessionID })
        if selectedTerminalSessionID == sessionID {
            selectedTerminalSessionID = orderedTerminalSessions().last?.id
        }
        if rememberClosed, let sessionToRemove {
            rememberClosedTerminalSession(sessionToRemove)
        }
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    private func append(actor: String, message: String) {
        events.insert(SessionEvent(actor: actor, message: message), at: 0)
    }

    private func resetOperationLog(for tool: ProgrammingTool, title: String) {
        operationLogs[tool] = ["\(timestampPrefix()) \(title)"]
    }

    private func appendOperationLog(for tool: ProgrammingTool, _ rawLine: String) {
        let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        operationLogs[tool, default: []].append("\(timestampPrefix()) \(trimmed)")
    }

    private func statusSummary(from output: String, fallback: String) -> String {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.last ?? fallback
    }

    private func appendOperationOutputLines(for tool: ProgrammingTool, _ output: String) {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for line in lines {
            appendOperationLog(for: tool, line)
        }
    }

    @discardableResult
    private func startTerminalSession(
        tool: ProgrammingTool,
        title: String,
        executable: String,
        arguments: [String],
        workingDirectory: String,
        statusMessage: String? = nil,
        eventMessage: String? = nil
    ) -> UUID? {
        rememberWorkspaceDirectory(workingDirectory)
        workspacePath = workingDirectory

        let runner = terminalRunnerFactory()
        let runtimeHintRunner = runner as? any RuntimeStateHintingTerminalRunner
        let usesRuntimeHinting = runtimeHintRunner != nil
        let sessionUsesCodexProtocolRuntime = tool == .codex && isCodexProtocolModeEnabled
        let requiresCodexProtocolBootstrap = sessionUsesCodexProtocolRuntime && runner is CLIGhosttyTerminalRunner

        var terminalEnvironmentValues = terminalEnvironment()
        var launchExecutable = executable
        var launchArguments = arguments
        var codexConversationID: String?

        if requiresCodexProtocolBootstrap {
            guard isDirectCodexLaunch(executable: executable, arguments: arguments) else {
                configOperationStatus = "Codex 会话仅支持协议驱动启动。请使用 Codex 会话入口。"
                return nil
            }

            do {
                let bootstrapResult = try codexConversationBootstrapperFactory().createConversation(
                    workingDirectory: workingDirectory,
                    environment: terminalEnvironmentValues,
                    timeout: 10.0
                )
                codexConversationID = bootstrapResult.conversationID
                let resumeLaunch = makeCodexResumeLaunchCommand(
                    baseExecutable: executable,
                    baseArguments: arguments,
                    conversationID: bootstrapResult.conversationID
                )
                launchExecutable = resumeLaunch.executable
                launchArguments = resumeLaunch.arguments
            } catch {
                configOperationStatus = error.localizedDescription
                append(actor: "System", message: error.localizedDescription)
                return nil
            }
        }

        let sessionID = UUID()
        let now = Date()
        let transcriptFilePath = prepareTerminalTranscriptFilePath(
            for: tool,
            sessionID: sessionID,
            startedAt: now
        )
        let session = CLITerminalSession(
            id: sessionID,
            tool: tool,
            title: title,
            executable: launchExecutable,
            arguments: launchArguments,
            workingDirectory: workingDirectory,
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            endedAt: nil,
            isRunning: true,
            exitCode: nil,
            outputBuffer: TerminalSessionOutputBuffer(
                maxBytes: maxTerminalOutputBytes,
                maxPreviewCharacters: maxTerminalOutputCharacters
            ),
            lastInput: nil,
            isRestoredSnapshot: false,
            transcriptFilePath: transcriptFilePath,
            codexConversationID: codexConversationID
        )

        terminalSessions.insert(session, at: 0)
        terminalSessionOrder.removeAll { $0 == sessionID }
        terminalSessionOrder.append(sessionID)
        selectedTerminalSessionID = sessionID
        applyRuntimeStateIfNeeded(
            sessionUsesCodexProtocolRuntime ? .syncing : .working,
            source: .lifecycle,
            for: sessionID
        )
        persistTerminalWorkspaceSnapshotIfNeeded()

        let shouldAttachNodeWrapper = !sessionUsesCodexProtocolRuntime && shouldUseNodeWrapper(
            for: tool,
            executable: launchExecutable,
            arguments: launchArguments
        )
        let ipcSocketPath: String?
        if shouldAttachNodeWrapper {
            let socketPath = startRuntimeIPCServer(for: sessionID, tool: tool)
            if let socketPath {
                terminalEnvironmentValues["AGENTOS_IPC_PATH"] = socketPath
            }
            ipcSocketPath = socketPath
        } else {
            ipcSocketPath = nil
        }
        let runtimeLaunch = wrappedTerminalLaunchCommand(
            tool: tool,
            baseExecutable: launchExecutable,
            baseArguments: launchArguments,
            ipcSocketPath: ipcSocketPath,
            transcriptFilePath: transcriptFilePath,
            sessionUsesCodexProtocolRuntime: sessionUsesCodexProtocolRuntime
        )
        var usesWrapperRuntimeSignals = runtimeLaunch.usesNodeWrapper

        let outputBuffer = session.outputBuffer
        runner.onOutput = { [weak self] raw in
            outputBuffer.append(raw)
            if sessionUsesCodexProtocolRuntime {
                return
            }
            guard !usesWrapperRuntimeSignals else {
                return
            }
            guard !usesRuntimeHinting else {
                return
            }
            let detectedState = TerminalSessionStateClassifier.classify(outputChunk: raw)
                ?? TerminalSessionStateClassifier.classify(text: outputBuffer.previewText())
            guard let detectedState else {
                return
            }
            Task { @MainActor in
                self?.applyRuntimeStateIfNeeded(
                    detectedState,
                    source: .heuristicOutput,
                    for: sessionID
                )
            }
        }
        runner.onWorkingDirectoryChange = { [weak self] directory in
            Task { @MainActor in
                self?.updateTerminalSessionWorkingDirectory(sessionID, directory: directory)
            }
        }
        runner.onExit = { [weak self] status in
            Task { @MainActor in
                self?.handleTerminalExit(sessionID: sessionID, exitCode: status)
            }
        }
        if let runtimeHintRunner {
            runtimeHintRunner.onRuntimeStateHint = { [weak self] runtimeState in
                Task { @MainActor in
                    guard !sessionUsesCodexProtocolRuntime else {
                        return
                    }
                    guard !usesWrapperRuntimeSignals else {
                        return
                    }
                    self?.applyRuntimeStateHint(runtimeState, for: sessionID)
                }
            }
        }

        do {
            do {
                try runner.start(
                    executable: runtimeLaunch.executable,
                    arguments: runtimeLaunch.arguments,
                    workingDirectory: workingDirectory,
                    environment: terminalEnvironmentValues
                )
            } catch {
                guard runtimeLaunch.usesNodeWrapper else {
                    throw error
                }
                usesWrapperRuntimeSignals = false
                stopRuntimeIPCServer(for: sessionID)
                terminalEnvironmentValues.removeValue(forKey: "AGENTOS_IPC_PATH")
                append(actor: "System", message: "Node Wrapper 启动失败，已回退直连模式：\(error.localizedDescription)")
                try runner.start(
                    executable: launchExecutable,
                    arguments: launchArguments,
                    workingDirectory: workingDirectory,
                    environment: terminalEnvironmentValues
                )
            }
            terminalRunners[sessionID] = runner
            if requiresCodexProtocolBootstrap, runner is CLIGhosttyTerminalRunner {
                guard let codexConversationID else {
                    markTerminalSessionAsFailed(
                        sessionID,
                        error: CLITerminalError.launchFailed("缺少 Codex 会话 ID，禁止进入猜测模式")
                    )
                    return nil
                }
                startCodexAppServerMonitor(
                    for: sessionID,
                    conversationID: codexConversationID,
                    workingDirectory: workingDirectory,
                    launchedAt: now,
                    environment: terminalEnvironmentValues
                )
            }
            configOperationStatus = statusMessage ?? "\(tool.title) 会话已启动"
            append(actor: "System", message: eventMessage ?? "已启动 \(tool.title) 内置终端会话")
        } catch {
            markTerminalSessionAsFailed(sessionID, error: error)
            return nil
        }

        return sessionID
    }

    private func isDirectCodexLaunch(executable: String, arguments: [String]) -> Bool {
        let normalizedExecutable = normalizedExecutableCommand(executable)
        if normalizedExecutable == "codex" {
            return true
        }

        if normalizedExecutable == "env",
           let firstArg = arguments.first {
            return normalizedExecutableCommand(firstArg) == "codex"
        }

        if normalizedExecutable == "env", arguments.isEmpty {
            return true
        }

        return false
    }

    private func makeCodexResumeLaunchCommand(
        baseExecutable: String,
        baseArguments: [String],
        conversationID: String
    ) -> (executable: String, arguments: [String]) {
        let normalizedExecutable = normalizedExecutableCommand(baseExecutable)
        if normalizedExecutable == "env" {
            var args = baseArguments
            if args.isEmpty {
                args.append("codex")
            }
            args.append("resume")
            args.append(conversationID)
            return (baseExecutable, args)
        }

        return (baseExecutable, baseArguments + ["resume", conversationID])
    }

    private func resolveProgrammingTool(from commandLine: String) -> ProgrammingTool? {
        guard let token = firstExecutableToken(in: commandLine) else {
            return nil
        }
        let normalizedCommand = normalizedExecutableCommand(token)
        guard !normalizedCommand.isEmpty else { return nil }

        guard let matchedTool = ProgrammingTool.allCases.first(where: { tool in
            tool.candidates.contains { candidate in
                candidate.caseInsensitiveCompare(normalizedCommand) == .orderedSame
            }
        }) else {
            return nil
        }

        return matchedTool
    }

    private func firstExecutableToken(in commandLine: String) -> String? {
        let assignmentPrefixes = ["export", "env", "/usr/bin/env"]
        let tokens = commandLine.split(whereSeparator: { $0.isWhitespace })
        for rawToken in tokens {
            let token = rawToken
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }

            if assignmentPrefixes.contains(token) {
                continue
            }

            if token.contains("="), !token.hasPrefix("/") {
                continue
            }

            return token
        }
        return nil
    }

    private func normalizedExecutableCommand(_ rawToken: String) -> String {
        let expanded = (rawToken as NSString).expandingTildeInPath
        let command = URL(fileURLWithPath: expanded).lastPathComponent
        return command.lowercased()
    }

    private func rememberQuickLaunchCommand(_ commandLine: String) {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentQuickLaunchCommands.removeAll { $0 == trimmed }
        recentQuickLaunchCommands.insert(trimmed, at: 0)
        if recentQuickLaunchCommands.count > maxRecentQuickLaunchCommands {
            recentQuickLaunchCommands = Array(recentQuickLaunchCommands.prefix(maxRecentQuickLaunchCommands))
        }
    }

    private func resolveLaunchCommand(for installation: ToolInstallation) -> (executable: String, arguments: [String])? {
        if let binaryPath = installation.binaryPath?.trimmingCharacters(in: .whitespacesAndNewlines), !binaryPath.isEmpty {
            let expanded = (binaryPath as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return (expanded, installation.tool.integratedTerminalArguments)
            }

            let fallbackName = URL(fileURLWithPath: expanded).lastPathComponent
            if !fallbackName.isEmpty {
                return (
                    executable: "/usr/bin/env",
                    arguments: [fallbackName] + installation.tool.integratedTerminalArguments
                )
            }
        }

        if let fallbackCandidate = installation.tool.candidates.first {
            return (
                executable: "/usr/bin/env",
                arguments: [fallbackCandidate] + installation.tool.integratedTerminalArguments
            )
        }

        return nil
    }

    private func resolvedWorkspacePath(overridePath: String? = nil) -> String? {
        let sourcePath = overridePath ?? workspacePath
        return normalizeDirectoryPath(sourcePath)
    }

    private func wrappedTerminalLaunchCommand(
        tool: ProgrammingTool,
        baseExecutable: String,
        baseArguments: [String],
        ipcSocketPath: String?,
        transcriptFilePath: String?,
        sessionUsesCodexProtocolRuntime: Bool
    ) -> TerminalRuntimeLaunchCommand {
        // Keep Ghostty session attached to the native PTY directly.
        // Wrapping with `/usr/bin/script` hurts TUI resize fidelity.
        _ = transcriptFilePath

        guard !sessionUsesCodexProtocolRuntime else {
            return TerminalRuntimeLaunchCommand(
                executable: baseExecutable,
                arguments: baseArguments,
                usesNodeWrapper: false
            )
        }
        guard let ipcSocketPath else {
            return TerminalRuntimeLaunchCommand(
                executable: baseExecutable,
                arguments: baseArguments,
                usesNodeWrapper: false
            )
        }
        guard shouldUseNodeWrapper(
            for: tool,
            executable: baseExecutable,
            arguments: baseArguments
        ) else {
            return TerminalRuntimeLaunchCommand(
                executable: baseExecutable,
                arguments: baseArguments,
                usesNodeWrapper: false
            )
        }

        guard let wrapperPath = try? AgentNodeWrapperScript.ensureInstalled() else {
            append(actor: "System", message: "Node Wrapper 写入失败，已回退直连模式。")
            return TerminalRuntimeLaunchCommand(
                executable: baseExecutable,
                arguments: baseArguments,
                usesNodeWrapper: false
            )
        }

        let wrapperArguments = [
            "node",
            wrapperPath,
            "--ipc-path",
            ipcSocketPath,
            "--tool",
            tool.rawValue,
            "--",
            baseExecutable,
        ] + baseArguments

        return TerminalRuntimeLaunchCommand(
            executable: "/usr/bin/env",
            arguments: wrapperArguments,
            usesNodeWrapper: true
        )
    }

    private func shouldUseNodeWrapper(
        for tool: ProgrammingTool,
        executable: String,
        arguments: [String]
    ) -> Bool {
        guard isNodeWrapperRuntimeEnabled else {
            return false
        }
        let wrapperSupportedTools: Set<ProgrammingTool> = [
            .codex,
            .claudeCode,
            .qwenCode,
            .opencode,
        ]
        guard wrapperSupportedTools.contains(tool) else {
            return false
        }
        return isDirectToolLaunch(for: tool, executable: executable, arguments: arguments)
    }

    private func isDirectToolLaunch(
        for tool: ProgrammingTool,
        executable: String,
        arguments: [String]
    ) -> Bool {
        let normalizedExecutable = normalizedExecutableCommand(executable)
        let candidateSet = Set(tool.candidates.map { $0.lowercased() })
        if candidateSet.contains(normalizedExecutable) {
            return true
        }

        if normalizedExecutable == "env",
           let firstArgument = arguments.first {
            return candidateSet.contains(normalizedExecutableCommand(firstArgument))
        }

        if normalizedExecutable == "env", arguments.isEmpty, tool == .codex {
            return true
        }

        return false
    }

    private func prepareTerminalTranscriptFilePath(
        for tool: ProgrammingTool,
        sessionID: UUID,
        startedAt: Date
    ) -> String? {
        let fileManager = FileManager.default
        guard var appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        appSupportURL.appendPathComponent("AgentOS", isDirectory: true)
        appSupportURL.appendPathComponent("TerminalTranscripts", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            append(actor: "System", message: "创建会话录制目录失败：\(error.localizedDescription)")
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: startedAt)
        let toolSlug = tool.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
        let shortID = sessionID.uuidString.prefix(8).lowercased()
        let filename = "\(timestamp)-\(toolSlug)-\(shortID).log"
        return appSupportURL.appendingPathComponent(filename, isDirectory: false).path
    }

    private func exportedTranscriptPayload(for session: CLITerminalSession) -> (text: String, sourceLabel: String) {
        if let runner = terminalRunners[session.id] as? CLIGhosttyTerminalRunner,
           let snapshot = runner.transcriptTextSnapshot(),
           !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (snapshot, "ghostty surface snapshot")
        }

        if let transcriptFilePath = session.transcriptFilePath,
           FileManager.default.fileExists(atPath: transcriptFilePath),
           let data = try? Data(contentsOf: URL(fileURLWithPath: transcriptFilePath)),
           !data.isEmpty {
            return (
                String(decoding: data, as: UTF8.self),
                "script recorder (\(transcriptFilePath))"
            )
        }
        return (session.outputBuffer.snapshotText(), "in-memory output buffer")
    }

    private func markdownCodeFence(for text: String) -> (opening: String, closing: String) {
        let lines = text.components(separatedBy: .newlines)
        let longestBacktickRun = lines.reduce(0) { partialResult, line in
            max(partialResult, longestRun(of: "`", in: line))
        }
        let count = max(3, longestBacktickRun + 1)
        let backticks = String(repeating: "`", count: count)
        return (opening: backticks + "text", closing: backticks)
    }

    private func longestRun(of token: Character, in text: String) -> Int {
        var maxRun = 0
        var currentRun = 0
        for character in text {
            if character == token {
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 0
            }
        }
        return maxRun
    }

    private func terminalEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment

        let home = NSHomeDirectory()
        let existingPathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let preferredEntries = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.nvm/current/bin",
        ]

        var mergedEntries: [String] = []
        for entry in existingPathEntries + preferredEntries where !entry.isEmpty {
            if !mergedEntries.contains(entry) {
                mergedEntries.append(entry)
            }
        }

        environment["PATH"] = mergedEntries.joined(separator: ":")
        environment["TERM"] = CLIGhosttyTerminalRunner.isGhosttyAvailable ? "xterm-ghostty" : "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "ghostty"
        return environment
    }

    private func startRuntimeIPCServer(for sessionID: UUID, tool _: ProgrammingTool) -> String? {
        stopRuntimeIPCServer(for: sessionID)
        let socketPath = runtimeSocketPath(for: sessionID)

        let server = AgentRuntimeIPCServer(
            configuration: .init(
                socketPath: socketPath,
                onEvent: { [weak self] event in
                    Task { @MainActor in
                        self?.handleRuntimeIPCEvent(event, sessionID: sessionID)
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        self?.append(actor: "System", message: "Runtime IPC: \(message)")
                    }
                }
            )
        )

        do {
            try server.start()
            terminalIPCServers[sessionID] = server
            terminalIPCSocketPaths[sessionID] = socketPath
            return socketPath
        } catch {
            append(actor: "System", message: "Runtime IPC 启动失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func stopRuntimeIPCServer(for sessionID: UUID) {
        if let server = terminalIPCServers.removeValue(forKey: sessionID) {
            server.stop()
        }
        if let socketPath = terminalIPCSocketPaths.removeValue(forKey: sessionID) {
            unlink(socketPath)
        }
        terminalPendingApprovals.removeValue(forKey: sessionID)
    }

    private func runtimeSocketPath(for sessionID: UUID) -> String {
        let shortID = String(sessionID.uuidString.prefix(8)).lowercased()
        return "/tmp/agentos-ipc-\(shortID).sock"
    }

    private func handleRuntimeIPCEvent(_ event: AgentRuntimeIPCEvent, sessionID: UUID) {
        applyRuntimeStateIfNeeded(event.runtimeState, source: .wrapperIPC, for: sessionID)

        if event.status == .approving {
            let prompt = event.approvalPrompt
                ?? event.message
                ?? "CLI 请求授权执行本次操作。"
            terminalPendingApprovals[sessionID] = TerminalApprovalRequest(
                prompt: prompt,
                receivedAt: Date()
            )
            return
        }

        terminalPendingApprovals.removeValue(forKey: sessionID)
    }

    private func startCodexAppServerMonitor(
        for sessionID: UUID,
        conversationID: String,
        workingDirectory: String,
        launchedAt: Date,
        environment: [String: String]
    ) {
        stopCodexAppServerMonitor(for: sessionID)

        let monitor = codexAppServerMonitorFactory(
            .init(
                conversationID: conversationID,
                workingDirectory: workingDirectory,
                launchedAt: launchedAt,
                environment: environment,
                onRuntimeState: { [weak self] runtimeState in
                    Task { @MainActor in
                        self?.applyRuntimeStateIfNeeded(
                            runtimeState,
                            source: .protocolEvent,
                            for: sessionID
                        )
                    }
                },
                onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self else { return }
                        self.applyRuntimeStateIfNeeded(
                            .unknown,
                            source: .protocolEvent,
                            for: sessionID
                        )
                        self.append(actor: "System", message: message)
                    }
                }
            )
        )
        codexAppServerMonitors[sessionID] = monitor
        monitor.start()
    }

    private func stopCodexAppServerMonitor(for sessionID: UUID) {
        guard let monitor = codexAppServerMonitors.removeValue(forKey: sessionID) else {
            return
        }
        monitor.stop()
    }

    private func persistGhosttySnapshotIfNeeded(from runner: CLIGhosttyTerminalRunner, sessionID: UUID) {
        guard let snapshot = runner.transcriptTextSnapshot() else {
            return
        }
        let trimmedSnapshot = snapshot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSnapshot.isEmpty else {
            return
        }
        guard let session = terminalSession(for: sessionID) else {
            return
        }

        let snapshotData = Data(snapshot.utf8)
        let existingData = session.outputBuffer.snapshotData()
        let existingTrimmed = String(decoding: existingData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !existingTrimmed.isEmpty, snapshotData.count <= existingData.count {
            return
        }

        session.outputBuffer.replace(with: snapshotData)
    }

    private func handleTerminalExit(sessionID: UUID, exitCode: Int32) {
        stopCodexAppServerMonitor(for: sessionID)
        stopRuntimeIPCServer(for: sessionID)
        if let runner = terminalRunners[sessionID] as? CLIGhosttyTerminalRunner {
            persistGhosttySnapshotIfNeeded(from: runner, sessionID: sessionID)
        }
        terminalRunners.removeValue(forKey: sessionID)
        terminalLastResize.removeValue(forKey: sessionID)

        mutateTerminalSession(sessionID) { session in
            guard session.isRunning else { return }
            session.isRunning = false
            session.exitCode = exitCode
            session.endedAt = Date()
            session.updatedAt = Date()
        }
        setRuntimeStateIfNeeded(exitCode == 0 ? .completedSuccess : .completedFailure, for: sessionID)

        guard let session = terminalSession(for: sessionID) else { return }
        configOperationStatus = "\(session.tool.title) 会话已结束（退出码 \(exitCode)）"
        terminalNotificationService.notifySessionCompleted(session)
        append(actor: "System", message: "\(session.tool.title) 终端会话结束，退出码 \(exitCode)")
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    private func markTerminalSessionAsFailed(_ sessionID: UUID, error: Error) {
        stopCodexAppServerMonitor(for: sessionID)
        stopRuntimeIPCServer(for: sessionID)
        let errorLine = "\n[\(timestampPrefix())] 启动失败：\(error.localizedDescription)"
        terminalSession(for: sessionID)?.outputBuffer.append(Data(errorLine.utf8))

        mutateTerminalSession(sessionID) { session in
            session.isRunning = false
            session.exitCode = 1
            session.endedAt = Date()
            session.updatedAt = Date()
        }

        configOperationStatus = "终端会话启动失败：\(error.localizedDescription)"
        setRuntimeStateIfNeeded(.completedFailure, for: sessionID)
        persistTerminalWorkspaceSnapshotIfNeeded()
    }

    private func mutateTerminalSession(_ sessionID: UUID, mutate: (inout CLITerminalSession) -> Void) {
        guard let index = terminalSessions.firstIndex(where: { $0.id == sessionID }) else { return }
        var session = terminalSessions[index]
        mutate(&session)
        terminalSessions[index] = session
    }

    private func resolvePendingTerminalApproval(_ sessionID: UUID, approved: Bool) {
        guard terminalPendingApprovals[sessionID] != nil else {
            return
        }
        terminalPendingApprovals.removeValue(forKey: sessionID)
        let answer = approved ? "y" : "n"
        sendTerminalData(Data((answer + "\n").utf8), to: sessionID, lastInput: answer)
    }

    private func applyRuntimeStateHint(_ runtimeState: TerminalSessionRuntimeState, for sessionID: UUID) {
        applyRuntimeStateIfNeeded(runtimeState, source: .runtimeHint, for: sessionID)
    }

    private func setRuntimeStateIfNeeded(_ runtimeState: TerminalSessionRuntimeState, for sessionID: UUID) {
        applyRuntimeStateIfNeeded(runtimeState, source: .lifecycle, for: sessionID)
    }

    private func isFinalRuntimeState(_ runtimeState: TerminalSessionRuntimeState) -> Bool {
        switch runtimeState {
        case .completedSuccess, .completedFailure, .restoredStopped, .stopped:
            return true
        case .syncing, .working, .waitingUserInput, .waitingApproval, .unknown:
            return false
        }
    }

    private func shouldPreferIncomingRuntimeState(
        _ incomingState: TerminalSessionRuntimeState,
        over existingState: TerminalSessionRuntimeState
    ) -> Bool {
        if isFinalRuntimeState(incomingState) {
            return true
        }

        switch incomingState {
        case .waitingApproval:
            return existingState == .working
                || existingState == .syncing
                || existingState == .unknown
                || existingState == .waitingUserInput
        case .waitingUserInput:
            return existingState == .working
                || existingState == .syncing
                || existingState == .unknown
        case .syncing, .working, .unknown, .completedSuccess, .completedFailure, .restoredStopped, .stopped:
            return false
        }
    }

    private func shouldKeepExistingWaitingState(
        _ existingState: TerminalSessionRuntimeState,
        incomingState: TerminalSessionRuntimeState,
        source: TerminalRuntimeSignalSource
    ) -> Bool {
        guard existingState == .waitingUserInput || existingState == .waitingApproval else {
            return false
        }
        guard !isFinalRuntimeState(incomingState) else {
            return false
        }

        switch incomingState {
        case .waitingUserInput, .waitingApproval:
            return false
        case .working, .syncing, .unknown:
            return source != .userInput && source != .protocolEvent
        case .completedSuccess, .completedFailure, .restoredStopped, .stopped:
            return false
        }
    }

    private func applyRuntimeStateIfNeeded(
        _ runtimeState: TerminalSessionRuntimeState,
        source: TerminalRuntimeSignalSource,
        for sessionID: UUID
    ) {
        guard terminalSessions.contains(where: { $0.id == sessionID }) else {
            stopCodexAppServerMonitor(for: sessionID)
            stopRuntimeIPCServer(for: sessionID)
            terminalRuntimeStates.removeValue(forKey: sessionID)
            terminalRuntimeStateSources.removeValue(forKey: sessionID)
            terminalPendingApprovals.removeValue(forKey: sessionID)
            return
        }

        if let existingState = terminalRuntimeStates[sessionID],
           shouldKeepExistingWaitingState(
               existingState,
               incomingState: runtimeState,
               source: source
           ) {
            return
        }

        let isUserInputResumingWaitingState: Bool
        if let existingState = terminalRuntimeStates[sessionID] {
            isUserInputResumingWaitingState = source == .userInput
                && runtimeState == .working
                && (existingState == .waitingUserInput || existingState == .waitingApproval)
        } else {
            isUserInputResumingWaitingState = false
        }

        if let existingSource = terminalRuntimeStateSources[sessionID],
           let existingState = terminalRuntimeStates[sessionID],
           source.priority < existingSource.priority,
           !isUserInputResumingWaitingState,
           !isFinalRuntimeState(existingState),
           !shouldPreferIncomingRuntimeState(runtimeState, over: existingState),
           !(existingSource == .lifecycle) {
            return
        }

        if terminalRuntimeStates[sessionID] == runtimeState,
           terminalRuntimeStateSources[sessionID] == source {
            return
        }

        terminalRuntimeStates[sessionID] = runtimeState
        terminalRuntimeStateSources[sessionID] = source
        if runtimeState != .waitingApproval {
            terminalPendingApprovals.removeValue(forKey: sessionID)
        }
    }

    static func truncateTerminalOutput(_ output: String, maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        guard output.count > maxCharacters else { return output }

        let truncated = String(output.suffix(maxCharacters))

        // If truncation cuts in the middle of a line (including ANSI fragments),
        // drop that first partial line to keep terminal rendering stable.
        guard let firstLineBreak = truncated.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            // No complete line boundary in current window; wait for subsequent chunks.
            return ""
        }

        var start = truncated.index(after: firstLineBreak)
        while start < truncated.endIndex {
            let current = truncated[start]
            if current == "\n" || current == "\r" {
                start = truncated.index(after: start)
                continue
            }
            break
        }

        guard start < truncated.endIndex else { return "" }
        return String(truncated[start...])
    }

    private func rememberWorkspaceDirectory(_ path: String) {
        guard let normalized = normalizeDirectoryPath(path) else { return }
        recentWorkspaceDirectories.removeAll { $0 == normalized }
        recentWorkspaceDirectories.insert(normalized, at: 0)
        recentWorkspaceDirectories = deduplicatedPaths(
            recentWorkspaceDirectories,
            limit: maxRecentWorkspaceDirectories
        )
    }

    private func rememberClosedTerminalSession(_ session: CLITerminalSession) {
        let record = ClosedTerminalSessionRecord(
            id: session.id,
            tool: session.tool,
            title: session.title,
            workingDirectory: session.workingDirectory,
            closedAt: Date()
        )

        recentlyClosedTerminalSessions.removeAll { $0.id == record.id }
        recentlyClosedTerminalSessions.insert(record, at: 0)
        if recentlyClosedTerminalSessions.count > maxRecentlyClosedTerminalSessions {
            recentlyClosedTerminalSessions = Array(
                recentlyClosedTerminalSessions.prefix(maxRecentlyClosedTerminalSessions)
            )
        }
    }

    private func normalizeDirectoryPath(_ rawPath: String) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return expanded
    }

    private func deduplicatedPaths(_ rawPaths: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var unique: [String] = []
        for path in rawPaths {
            guard let normalized = normalizeDirectoryPath(path) else { continue }
            if !unique.contains(normalized) {
                unique.append(normalized)
            }
            if unique.count >= limit {
                break
            }
        }
        return unique
    }

    private func resolveTerminalReportedDirectory(_ rawDirectory: String?) -> String? {
        guard let rawDirectory else { return nil }
        let trimmed = rawDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.isFileURL {
            if let normalized = normalizeDirectoryPath(url.path) {
                return normalized
            }
        }

        if let decoded = trimmed.removingPercentEncoding,
           let normalized = normalizeDirectoryPath(decoded) {
            return normalized
        }

        return normalizeDirectoryPath(trimmed)
    }

    private func restoreTerminalWorkspaceSnapshotIfNeeded() {
        guard isTerminalWorkspacePersistenceEnabled else { return }
        guard let data = userDefaults.data(forKey: terminalWorkspaceSnapshotStorageKey) else { return }
        guard let snapshot = try? JSONDecoder().decode(PersistedTerminalWorkspaceSnapshot.self, from: data) else { return }
        guard snapshot.schemaVersion == PersistedTerminalWorkspaceSnapshot.currentSchemaVersion else { return }

        workspacePath = normalizeDirectoryPath(snapshot.workspacePath) ?? ""
        recentWorkspaceDirectories = deduplicatedPaths(
            snapshot.recentDirectories,
            limit: maxRecentWorkspaceDirectories
        )
        favoriteWorkspaceDirectories = deduplicatedPaths(
            snapshot.favoriteDirectories,
            limit: maxFavoriteWorkspaceDirectories
        )
        recentlyClosedTerminalSessions = (snapshot.recentlyClosedSessions ?? []).compactMap { stored in
            guard let tool = ProgrammingTool(rawValue: stored.tool) else { return nil }
            guard let workingDirectory = normalizeDirectoryPath(stored.workingDirectory) else { return nil }
            return ClosedTerminalSessionRecord(
                id: stored.id,
                tool: tool,
                title: stored.title,
                workingDirectory: workingDirectory,
                closedAt: stored.closedAt
            )
        }
        terminalRuntimeStates = [:]
        terminalRuntimeStateSources = [:]
        terminalPendingApprovals = [:]

        terminalSessions = snapshot.sessions.compactMap { stored in
            guard let tool = ProgrammingTool(rawValue: stored.tool) else { return nil }
            guard let workingDirectory = normalizeDirectoryPath(stored.workingDirectory) else { return nil }
            let previewText = stored.outputPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            let hydratedPreview = previewText.isEmpty
                ? ""
                : "[恢复快照] 上次会话摘要（仅元数据）：\n\(previewText)\n"

            return CLITerminalSession(
                id: stored.id,
                tool: tool,
                title: stored.title,
                executable: stored.executable,
                arguments: stored.arguments,
                workingDirectory: workingDirectory,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                startedAt: stored.startedAt,
                endedAt: stored.endedAt,
                isRunning: false,
                exitCode: stored.exitCode,
                outputBuffer: TerminalSessionOutputBuffer(
                    initialData: Data(hydratedPreview.utf8),
                    maxBytes: maxTerminalOutputBytes,
                    maxPreviewCharacters: maxTerminalOutputCharacters
                ),
                lastInput: stored.lastInput,
                isRestoredSnapshot: true,
                transcriptFilePath: stored.transcriptFilePath,
                codexConversationID: stored.codexConversationID
            )
        }

        terminalSessionOrder = restoredTerminalSessionOrder(from: snapshot.sessionOrder)

        if let selectedSessionID = snapshot.selectedSessionID,
           terminalSessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedTerminalSessionID = selectedSessionID
        } else {
            self.selectedTerminalSessionID = orderedTerminalSessions().last?.id
        }
    }

    private func persistTerminalWorkspaceSnapshotIfNeeded() {
        guard isTerminalWorkspacePersistenceEnabled else { return }

        let orderedSessions = orderedTerminalSessions()
        let sessions = orderedSessions
            .suffix(maxPersistedTerminalSessions)
            .map { session in
                PersistedTerminalSessionSnapshot(
                    id: session.id,
                    tool: session.tool.rawValue,
                    title: session.title,
                    executable: session.executable,
                    arguments: session.arguments,
                    workingDirectory: session.workingDirectory,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    exitCode: session.exitCode,
                    lastInput: session.lastInput,
                    outputPreview: session.outputPreview,
                    transcriptFilePath: session.transcriptFilePath,
                    codexConversationID: session.codexConversationID
                )
            }

        let snapshot = PersistedTerminalWorkspaceSnapshot(
            schemaVersion: PersistedTerminalWorkspaceSnapshot.currentSchemaVersion,
            workspacePath: workspacePath,
            recentDirectories: deduplicatedPaths(
                recentWorkspaceDirectories,
                limit: maxRecentWorkspaceDirectories
            ),
            favoriteDirectories: deduplicatedPaths(
                favoriteWorkspaceDirectories,
                limit: maxFavoriteWorkspaceDirectories
            ),
            recentlyClosedSessions: recentlyClosedTerminalSessions
                .prefix(maxRecentlyClosedTerminalSessions)
                .map { record in
                    PersistedClosedTerminalSessionSnapshot(
                        id: record.id,
                        tool: record.tool.rawValue,
                        title: record.title,
                        workingDirectory: record.workingDirectory,
                        closedAt: record.closedAt
                    )
                },
            sessionOrder: Array(sessions.map(\.id)),
            selectedSessionID: selectedTerminalSessionID,
            sessions: sessions
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults.set(data, forKey: terminalWorkspaceSnapshotStorageKey)
    }

    private func timestampPrefix() -> String {
        Date.now.formatted(date: .omitted, time: .standard)
    }

    private func normalizedTerminalSessionOrder() -> [UUID] {
        let sessions = terminalSessions
        guard !sessions.isEmpty else { return [] }

        let availableIDs = Set(sessions.map(\.id))
        var orderedIDs: [UUID] = []
        var consumedIDs = Set<UUID>()

        for sessionID in terminalSessionOrder where availableIDs.contains(sessionID) {
            guard consumedIDs.insert(sessionID).inserted else { continue }
            orderedIDs.append(sessionID)
        }

        let remainingIDs = sessions
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)
            .filter { !consumedIDs.contains($0) }
        orderedIDs.append(contentsOf: remainingIDs)
        return orderedIDs
    }

    private func restoredTerminalSessionOrder(from persistedOrder: [UUID]?) -> [UUID] {
        let orderedByCreation = terminalSessions
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)

        guard let persistedOrder, !persistedOrder.isEmpty else {
            return orderedByCreation
        }

        let availableIDs = Set(orderedByCreation)
        var normalized: [UUID] = []
        var consumedIDs = Set<UUID>()

        for sessionID in persistedOrder where availableIDs.contains(sessionID) {
            guard consumedIDs.insert(sessionID).inserted else { continue }
            normalized.append(sessionID)
        }

        for sessionID in orderedByCreation where !consumedIDs.contains(sessionID) {
            normalized.append(sessionID)
        }
        return normalized
    }
}
