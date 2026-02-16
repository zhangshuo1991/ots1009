import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AppState {
    private let detectionService: CLIDetectionService
    let installationService: ToolInstallationService
    let configEditorService: ConfigEditorService

    var installations: [ToolInstallation] = []
    var selectedToolForConfig: ProgrammingTool?
    var showingConfigEditor = false
    var configOperationStatus = ""

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

    init(
        detectionService: CLIDetectionService = CLIDetectionService(),
        installationService: ToolInstallationService = ToolInstallationService(),
        configEditorService: ConfigEditorService = ConfigEditorService()
    ) {
        self.detectionService = detectionService
        self.installationService = installationService
        self.configEditorService = configEditorService
        refreshDetections()
        refreshInstallations()
    }

    func saveWorkspace(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspacePath = trimmed
        append(actor: "System", message: "工作目录已保存：\(trimmed)")
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
        let installedCount = installations.filter(\.isInstalled).count
        append(actor: "System", message: "工具安装检测完成：\(installedCount)/\(installations.count) 已安装")
    }

    func openConfigDirectory(for tool: ProgrammingTool) {
        let success = installationService.openConfigDirectory(for: tool)
        if success {
            configOperationStatus = "已打开配置目录"
        } else {
            configOperationStatus = "无法打开配置目录"
        }
    }

    func openInstallDirectory(for tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool }) else {
            configOperationStatus = "未找到安装信息"
            return
        }
        let success = installationService.openInstallDirectory(for: installation)
        if success {
            configOperationStatus = "已打开安装目录"
        } else {
            configOperationStatus = "无法打开安装目录"
        }
    }

    func updateTool(_ tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具"
            return
        }

        let service = installationService
        Task { @MainActor in
            do {
                let output = try await service.updateTool(installation)
                configOperationStatus = output.isEmpty ? "更新完成" : output
                refreshInstallations()
                refreshDetections()
            } catch {
                configOperationStatus = "更新失败: \(error.localizedDescription)"
            }
        }
    }

    func uninstallTool(_ tool: ProgrammingTool) {
        guard let installation = installations.first(where: { $0.tool == tool && $0.isInstalled }) else {
            configOperationStatus = "未安装该工具"
            return
        }

        let service = installationService
        Task { @MainActor in
            do {
                let output = try await service.uninstallTool(installation)
                configOperationStatus = output.isEmpty ? "卸载完成" : output
                refreshInstallations()
                refreshDetections()
            } catch {
                configOperationStatus = "卸载失败: \(error.localizedDescription)"
            }
        }
    }

    private func append(actor: String, message: String) {
        events.insert(SessionEvent(actor: actor, message: message), at: 0)
    }
}
