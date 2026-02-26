import AppKit
import Darwin
import Foundation
import Testing
@testable import AgentOS

@MainActor
struct AppStateTests {
    @Test
    func selectingAgentSwitchesModelList() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.selectedModel = "gpt-5-codex"
        state.selectedAgent = .claude

        #expect(state.selectedAgent == .claude)
        #expect(state.selectedAgent.models.contains(state.selectedModel))
    }

    @Test
    func refreshDetectionsProducesAllTools() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.refreshDetections()

        #expect(state.detectionStatuses.count == ProgrammingTool.allCases.count)
    }

    @Test
    func installationSummaryCountsStayBalanced() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.refreshInstallations()

        #expect(state.installedToolCount + state.uninstalledToolCount == state.installations.count)
    }

    @Test
    func configEditorSelectionLifecycle() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.openConfigEditor(for: .codex)
        #expect(state.selectedToolForConfig == .codex)

        state.dismissConfigEditor()
        #expect(state.selectedToolForConfig == nil)
    }

    @Test
    func installationLookupReturnsNilForMissingTool() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        #expect(state.installation(for: nil) == nil)
    }

    @Test
    func openConfigEditorBlocksUnsupportedTool() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.openConfigEditor(for: .cursor)

        #expect(state.selectedToolForConfig == nil)
        #expect(state.configOperationStatus.contains("不支持在本应用直接编辑参数"))
    }

    @Test
    func openConfigEditorAllowsCodex() {
        let state = AppState(detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []))

        state.openConfigEditor(for: .codex)

        #expect(state.selectedToolForConfig == .codex)
        #expect(state.configOperationStatus.contains("正在打开 Codex 设置面板"))
    }

    @Test
    func terminalSessionLifecycleSendsCompletionNotification() async {
        let runner = MockTerminalRunner()
        let notificationSpy = NotificationSpy()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalNotificationService: notificationSpy,
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: nil,
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]
        state.saveWorkspace(path: NSHomeDirectory())

        let sessionID = state.createTerminalSession(for: .codex)
        #expect(sessionID != nil)
        if runner.startedExecutable == "/usr/bin/script" {
            #expect(runner.startedArguments.count >= 3)
            #expect(runner.startedArguments.first == "-q")
            #expect(runner.startedArguments[2] == "/usr/bin/env")
        } else {
            #expect(runner.startedExecutable == "/usr/bin/env")
        }
        if let sessionID {
            #expect(state.terminalSession(for: sessionID)?.transcriptFilePath != nil)
        }

        if let sessionID {
            #expect(state.terminalRuntimeState(for: sessionID) == .working)
            state.sendTerminalInput("help", to: sessionID)
            #expect(runner.sentInputs.last == "help\n")

            runner.emitOutput("hello world\n")
            try? await Task.sleep(nanoseconds: 100_000_000)
            #expect(state.terminalSession(for: sessionID)?.output.contains("hello world") == true)

            runner.emitExit(0)
            await Task.yield()
            #expect(state.terminalSession(for: sessionID)?.isRunning == false)
            #expect(state.terminalSession(for: sessionID)?.exitCode == 0)
            #expect(state.terminalRuntimeState(for: sessionID) == .completedSuccess)
            #expect(notificationSpy.notifiedSessionIDs == [sessionID])
        }
    }

    @Test
    func terminalRuntimeStateDetectsApprovalAndReturnsToWorkingAfterInputForNonCodexCLI() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("Approval required: allow this command? (y/N)\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingApproval)

        state.sendTerminalInput("y", to: sessionID)
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
    }

    @Test
    func terminalRuntimeStateDetectsWaitingUserInputFromOutputForNonCodexCLI() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("Waiting for input: enter your choice\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func terminalRuntimeStateDetectsPromptLineAsWaitingInputForNonCodexCLI() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("› Write tests for @filename\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func terminalRuntimeStateDetectsAnsiPromptLineAsWaitingInputForNonCodexCLI() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("\u{001B}[1;32m›\u{001B}[0m Continue\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func codexRuntimeHintsApplyInClassicMode() async {
        let runner = MockRuntimeHintRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            isNodeWrapperRuntimeEnabled: false
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: nil,
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitRuntimeHint(.waitingUserInput)
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func codexOutputKeywordUpdatesRuntimeStateInClassicMode() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            isNodeWrapperRuntimeEnabled: false
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("Waiting for input: enter your choice\\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
        #expect(state.runtimeStateSource(for: sessionID) == .heuristicOutput)
    }

    @Test
    func codexSessionDefaultsToWorkingInClassicMode() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            isNodeWrapperRuntimeEnabled: false
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .lifecycle)
    }

    @Test
    func codexSessionUsesNodeWrapperWhenDirectLaunch() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: nil,
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace)
        #expect(sessionID != nil)
        #expect(runner.startedExecutable == "/usr/bin/env")
        #expect(runner.startedArguments.first == "node")
        #expect(runner.startedArguments.contains("--ipc-path"))
        #expect(runner.startedArguments.contains("--"))
    }

    @Test
    func nodeWrapperScriptUsesPseudoTTYLauncher() throws {
        let scriptPath = try AgentNodeWrapperScript.ensureInstalled()
        let scriptContent = try String(contentsOfFile: scriptPath, encoding: .utf8)
        #expect(scriptContent.contains("spawn('/usr/bin/script'"))
        #expect(scriptContent.contains("stdio: ['inherit', 'pipe', 'pipe']"))
    }

    @Test
    func lifecycleStateOverridesHeuristicStateWhenSessionEnds() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            isNodeWrapperRuntimeEnabled: false
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("Waiting for input: enter your choice\\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
        #expect(state.runtimeStateSource(for: sessionID) == .heuristicOutput)

        runner.emitExit(0)
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .completedSuccess)
        #expect(state.runtimeStateSource(for: sessionID) == .lifecycle)
    }

    @Test
    func runtimeIPCApprovalEventSupportsNativeApprovalLoop() async throws {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }
        guard let socketPath = runner.startedEnvironment["AGENTOS_IPC_PATH"], !socketPath.isEmpty else {
            Issue.record("缺少 AGENTOS_IPC_PATH")
            return
        }

        try sendRuntimeIPCEvent(
            socketPath: socketPath,
            line: #"{"status":"approving","message":"Allow this command?","approvalPrompt":"Allow this command?"}"#
        )
        try? await Task.sleep(nanoseconds: 160_000_000)

        #expect(state.terminalRuntimeState(for: sessionID) == .waitingApproval)
        #expect(state.runtimeStateSource(for: sessionID) == .wrapperIPC)
        #expect(state.pendingApprovalRequest(for: sessionID)?.prompt == "Allow this command?")

        state.approvePendingTerminalAction(sessionID)
        await Task.yield()
        #expect(runner.sentInputs.last == "y\n")
        #expect(state.pendingApprovalRequest(for: sessionID) == nil)
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .userInput)
    }

    @Test
    func runtimeHintIsIgnoredWhenWrapperSignalsAreActive() async throws {
        let runner = MockRuntimeHintTrackingRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }
        guard let socketPath = runner.startedEnvironment["AGENTOS_IPC_PATH"], !socketPath.isEmpty else {
            Issue.record("缺少 AGENTOS_IPC_PATH")
            return
        }

        try sendRuntimeIPCEvent(
            socketPath: socketPath,
            line: #"{"status":"thinking","message":"wrapper_spawn"}"#
        )
        try? await Task.sleep(nanoseconds: 160_000_000)
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .wrapperIPC)

        runner.emitRuntimeHint(.waitingUserInput)
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .wrapperIPC)
    }

    @Test
    func wrapperWaitingUserInputRemainsStableUntilUserInputArrives() async throws {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }
        guard let socketPath = runner.startedEnvironment["AGENTOS_IPC_PATH"], !socketPath.isEmpty else {
            Issue.record("缺少 AGENTOS_IPC_PATH")
            return
        }

        try sendRuntimeIPCEvent(
            socketPath: socketPath,
            line: #"{"status":"awaiting_user","message":"prompt"}"#
        )
        try? await Task.sleep(nanoseconds: 160_000_000)
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
        #expect(state.runtimeStateSource(for: sessionID) == .wrapperIPC)

        try sendRuntimeIPCEvent(
            socketPath: socketPath,
            line: #"{"status":"thinking","message":"spurious"}"#
        )
        try? await Task.sleep(nanoseconds: 160_000_000)
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
        #expect(state.runtimeStateSource(for: sessionID) == .wrapperIPC)

        state.sendTerminalInput("continue", to: sessionID)
        await Task.yield()
        #expect(runner.sentInputs.last == "continue\n")
        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .userInput)
    }

    @Test
    func runtimeHintRunnerSupportsWorkingToWaitingTransition() async {
        let runner = MockRuntimeHintRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitRuntimeHint(.working)
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .working)

        runner.emitRuntimeHint(.waitingUserInput)
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func sendTerminalInputUsesLowestPriorityWorkingState() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.sendTerminalInput("help", to: sessionID)
        await Task.yield()

        #expect(state.terminalRuntimeState(for: sessionID) == .working)
        #expect(state.runtimeStateSource(for: sessionID) == .userInput)
    }

    @Test
    func terminalRuntimeStateDetectsPromptLineWithZeroWidthPrefixForNonCodexCLI() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("\u{200B}› Continue\n")
        await Task.yield()
        #expect(state.terminalRuntimeState(for: sessionID) == .waitingUserInput)
    }

    @Test
    func terminalSessionCreationFailsWhenToolNotInstalled() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: nil,
                isInstalled: false,
                installMethod: .unknown,
                installLocation: nil,
                version: nil
            )
        ]

        let sessionID = state.createTerminalSession(for: .codex)
        #expect(sessionID == nil)
        #expect(state.configOperationStatus.contains("未安装"))
    }

    @Test
    func terminalSessionResizePropagatesToRunner() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]
        state.saveWorkspace(path: NSHomeDirectory())

        guard let sessionID = state.createTerminalSession(for: .codex) else {
            Issue.record("会话创建失败")
            return
        }

        state.resizeTerminalSession(sessionID, cols: 160, rows: 42)

        #expect(runner.resizeEvents.count == 1)
        #expect(runner.resizeEvents.first?.cols == 160)
        #expect(runner.resizeEvents.first?.rows == 42)
    }

    @Test
    func terminalSessionUsesExplicitWorkingDirectory() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let explicitPath = FileManager.default.temporaryDirectory.path
        state.saveWorkspace(path: NSHomeDirectory())

        let sessionID = state.createTerminalSession(for: .codex, workingDirectory: explicitPath)

        #expect(sessionID != nil)
        #expect(runner.startedWorkingDirectory == explicitPath)
        if let sessionID {
            #expect(state.terminalSession(for: sessionID)?.workingDirectory == explicitPath)
        }
    }

    @Test
    func quickLaunchCommandCreatesSessionWithZsh() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        let workspace = FileManager.default.temporaryDirectory.path
        let sessionID = state.createTerminalSession(from: "claude --continue", workingDirectory: workspace)

        #expect(sessionID != nil)
        #expect(runner.startedExecutable == "/bin/zsh")
        #expect(runner.startedArguments == ["-lc", "claude --continue"])
        #expect(state.recentQuickLaunchCommands.first == "claude --continue")
        if let sessionID {
            #expect(state.terminalSession(for: sessionID)?.tool == .claudeCode)
            #expect(state.terminalSession(for: sessionID)?.workingDirectory == workspace)
        }
    }

    @Test
    func quickLaunchCommandSkipsEnvAssignmentsAndResolvesTool() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        let workspace = FileManager.default.temporaryDirectory.path
        let sessionID = state.createTerminalSession(
            from: "OPENAI_API_KEY=test /usr/bin/env codex --approval-mode auto",
            workingDirectory: workspace
        )

        #expect(sessionID != nil)
        if let sessionID {
            #expect(state.terminalSession(for: sessionID)?.tool == .codex)
        }
    }

    @Test
    func quickLaunchCommandRejectsUnsupportedCLI() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        let workspace = FileManager.default.temporaryDirectory.path
        let sessionID = state.createTerminalSession(from: "unknown-cli --help", workingDirectory: workspace)

        #expect(sessionID == nil)
        #expect(state.configOperationStatus.contains("无法识别命令对应的编程 CLI"))
    }

    @Test
    func terminalSessionEnvironmentCarriesGhosttyMarkers() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace)
        #expect(sessionID != nil)

        let expectedTerm = CLIGhosttyTerminalRunner.isGhosttyAvailable ? "xterm-ghostty" : "xterm-256color"
        #expect(runner.startedEnvironment["TERM"] == expectedTerm)
        #expect(runner.startedEnvironment["COLORTERM"] == "truecolor")
        #expect(runner.startedEnvironment["TERM_PROGRAM"] == "ghostty")
        #expect((runner.startedEnvironment["PATH"] ?? "").contains("/opt/homebrew/bin"))
        #expect(!(runner.startedEnvironment["AGENTOS_IPC_PATH"] ?? "").isEmpty)
    }

    @Test
    func ghosttyRunnerBackendSelectionSmokeTest() {
        let runner = CLIGhosttyTerminalRunner()
        let isAvailable = CLIGhosttyTerminalRunner.isGhosttyAvailable

        do {
            try runner.start(
                executable: "/usr/bin/env",
                arguments: [],
                workingDirectory: FileManager.default.temporaryDirectory.path,
                environment: ProcessInfo.processInfo.environment
            )

            #expect(isAvailable)
            #expect(runner.backendKind == CLIGhosttyTerminalRunner.BackendKind.ghosttyMetal)
            #expect(runner.isMetalRendering)
        } catch {
            #expect(!isAvailable)
            #expect(runner.backendKind == CLIGhosttyTerminalRunner.BackendKind.unavailable)
            #expect(!runner.isMetalRendering)
        }
    }

    @Test
    func ghosttyRunnerReusesHostViewAcrossLayoutRebuild() {
        let runner = CLIGhosttyTerminalRunner()

        let first = runner.reusableHostView { view in
            view.configure(
                onSendData: { _ in },
                onResize: { _, _ in },
                isRunning: true
            )
        }

        let second = runner.reusableHostView { view in
            view.configure(
                onSendData: { _ in },
                onResize: { _, _ in },
                isRunning: true
            )
        }

        #expect(first === second)
    }

    @Test
    func truncateTerminalOutputDropsLeadingPartialLine() {
        let partialANSI = "50;150;150;49m codex\n"
        let stableLine = "next line\n"
        let source = "prefix\n" + partialANSI + stableLine

        let result = AppState.truncateTerminalOutput(source, maxCharacters: 28)

        #expect(result == stableLine)
    }

    @Test
    func truncateTerminalOutputKeepsContentWhenWithinLimit() {
        let source = "hello\nworld\n"
        let result = AppState.truncateTerminalOutput(source, maxCharacters: 64)
        #expect(result == source)
    }

    @Test
    func truncateTerminalOutputUsesCarriageReturnAsBoundary() {
        let source = "prefix\r2;150;150;150;49mrti\rstable\r"
        let result = AppState.truncateTerminalOutput(source, maxCharacters: 18)
        #expect(result == "stable\r")
    }

    @Test
    func truncateTerminalOutputReturnsEmptyWhenNoBoundaryExists() {
        let source = "0;0;0;49mrvers"
        let result = AppState.truncateTerminalOutput(source, maxCharacters: 8)
        #expect(result.isEmpty)
    }

    @Test
    func terminalSessionCreationFailsWhenWorkspaceMissing() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let sessionID = state.createTerminalSession(for: .codex)

        #expect(sessionID == nil)
        #expect(state.configOperationStatus.contains("请先选择工作目录"))
    }

    @Test
    func workspaceRecentDirectoriesDeduplicatedAndCapped() throws {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentos-recent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        var createdPaths: [String] = []
        for index in 0..<24 {
            let path = baseDirectory.appendingPathComponent("workspace-\(index)", isDirectory: true).path
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            createdPaths.append(path)
            state.saveWorkspace(path: path)
        }

        if let duplicatePath = createdPaths.dropLast().last {
            state.saveWorkspace(path: duplicatePath)
            #expect(state.recentWorkspaceDirectories.first == duplicatePath)
        }

        #expect(state.recentWorkspaceDirectories.count <= 20)
        let uniqueCount = Set(state.recentWorkspaceDirectories).count
        #expect(uniqueCount == state.recentWorkspaceDirectories.count)
    }

    @Test
    func workspaceFavoriteDirectoriesToggle() throws {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentos-favorite-\(UUID().uuidString)", isDirectory: true)
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: path) }

        state.toggleFavoriteWorkspaceDirectory(path)
        #expect(state.isFavoriteWorkspaceDirectory(path))
        #expect(state.favoriteWorkspaceDirectories.contains(path))

        state.toggleFavoriteWorkspaceDirectory(path)
        #expect(!state.isFavoriteWorkspaceDirectory(path))
        #expect(!state.favoriteWorkspaceDirectories.contains(path))
    }

    @Test
    func terminalWorkspaceSnapshotRestoresSessions() {
        let suiteName = "agentos-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("无法创建测试 UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            userDefaults: defaults,
            terminalWorkspaceSnapshotStorageKey: "agentos.tests.snapshot",
            isTerminalWorkspacePersistenceEnabled: true
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        state.saveWorkspace(path: workspace)
        let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace)
        #expect(sessionID != nil)

        let restored = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalOutputFlushDelayNanos: 1,
            userDefaults: defaults,
            terminalWorkspaceSnapshotStorageKey: "agentos.tests.snapshot",
            isTerminalWorkspacePersistenceEnabled: true
        )

        #expect(restored.terminalSessions.count == 1)
        #expect(restored.terminalSessions.first?.isRunning == false)
        #expect(restored.terminalSessions.first?.isRestoredSnapshot == true)
        #expect(restored.recentWorkspaceDirectories.contains(workspace))
    }

    @Test
    func moveTerminalSessionUpdatesOrder() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let first = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let second = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let third = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        #expect(state.orderedTerminalSessions().map(\.id) == [first, second, third])

        state.moveTerminalSession(third, toIndex: 0)
        #expect(state.orderedTerminalSessions().map(\.id) == [third, first, second])
    }

    @Test
    func renameTerminalSessionUpdatesTitle() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.renameTerminalSession(sessionID, title: "我的任务会话")
        #expect(state.terminalSession(for: sessionID)?.title == "我的任务会话")
    }

    @Test
    func duplicateTerminalSessionCreatesSameDirectorySession() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sourceID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.renameTerminalSession(sourceID, title: "原始会话")
        let duplicatedID = state.duplicateTerminalSession(sourceID)

        #expect(duplicatedID != nil)
        if let duplicatedID {
            #expect(state.terminalSession(for: duplicatedID)?.workingDirectory == workspace)
            #expect(state.terminalSession(for: duplicatedID)?.title == "原始会话 副本")
        }
    }

    @Test
    func removingTerminalSessionKeepsOrderConsistent() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let first = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let second = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let third = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.moveTerminalSession(third, toIndex: 0)
        state.removeTerminalSession(first)

        #expect(state.orderedTerminalSessions().map(\.id) == [third, second])
        #expect(!state.terminalSessionOrder.contains(first))
    }

    @Test
    func terminalWorkspaceSnapshotRestoresSessionOrder() {
        let suiteName = "agentos-tests-order-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("无法创建测试 UserDefaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1,
            userDefaults: defaults,
            terminalWorkspaceSnapshotStorageKey: "agentos.tests.snapshot.order",
            isTerminalWorkspacePersistenceEnabled: true
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let first = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let second = state.createTerminalSession(for: .codex, workingDirectory: workspace),
              let third = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.moveTerminalSession(third, toIndex: 0)
        state.moveTerminalSession(second, toIndex: 1)

        let restored = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalOutputFlushDelayNanos: 1,
            userDefaults: defaults,
            terminalWorkspaceSnapshotStorageKey: "agentos.tests.snapshot.order",
            isTerminalWorkspacePersistenceEnabled: true
        )

        #expect(restored.orderedTerminalSessions().map(\.id) == [third, second, first])
    }

    @Test
    func terminalSessionWorkingDirectoryUpdatesFromOSCFileURL() throws {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentos-osc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstPath = root.appendingPathComponent("a", isDirectory: true).path
        let secondPath = root.appendingPathComponent("b with space", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: firstPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: secondPath, withIntermediateDirectories: true)

        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: firstPath) else {
            Issue.record("会话创建失败")
            return
        }

        let reportedURL = URL(fileURLWithPath: secondPath, isDirectory: true).absoluteString
        state.updateTerminalSessionWorkingDirectory(sessionID, directory: reportedURL)

        #expect(state.terminalSession(for: sessionID)?.workingDirectory == secondPath)
        #expect(state.recentWorkspaceDirectories.first == secondPath)
    }

    @Test
    func terminalSessionWorkingDirectoryIgnoresInvalidOSCValue() throws {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.updateTerminalSessionWorkingDirectory(sessionID, directory: "file:///path/not/exist")

        #expect(state.terminalSession(for: sessionID)?.workingDirectory == workspace)
    }

    @Test
    func reopenClosedTerminalSessionRestartsInSameDirectory() throws {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        state.removeTerminalSession(sessionID)
        #expect(state.recentlyClosedTerminalSessions.count == 1)

        let reopenedID = state.reopenLastClosedTerminalSession()
        #expect(reopenedID != nil)
        #expect(runner.startedWorkingDirectory == workspace)
        if let reopenedID {
            #expect(state.terminalSession(for: reopenedID)?.workingDirectory == workspace)
        }
    }

    @Test
    func clearTerminalSessionBufferRemovesOutputData() async {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        guard let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) else {
            Issue.record("会话创建失败")
            return
        }

        runner.emitOutput("hello\nworld\n")
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(state.terminalSession(for: sessionID)?.outputData.isEmpty == false)

        state.clearTerminalSessionBuffer(sessionID)

        #expect(state.terminalSession(for: sessionID)?.output.isEmpty == true)
        #expect(state.terminalSession(for: sessionID)?.outputData.isEmpty == true)
    }

    @Test
    func closeCurrentTerminalSessionClosesSelectedSession() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            ),
            ToolInstallation(
                tool: .claudeCode,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/claude",
                version: "1.0.0"
            ),
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        let first = state.createTerminalSession(for: .codex, workingDirectory: workspace)
        let second = state.createTerminalSession(for: .claudeCode, workingDirectory: workspace)
        #expect(first != nil)
        #expect(second != nil)
        if let first {
            state.selectTerminalSession(first)
            _ = state.closeCurrentTerminalSession()
            #expect(state.terminalSession(for: first) == nil)
        }
    }

    @Test
    func clearRecentlyClosedTerminalSessionsRemovesHistory() {
        let runner = MockTerminalRunner()
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            terminalRunnerFactory: { runner },
            terminalOutputFlushDelayNanos: 1
        )

        state.installations = [
            ToolInstallation(
                tool: .codex,
                binaryPath: "/usr/bin/env",
                isInstalled: true,
                installMethod: .npm,
                installLocation: "/tmp/codex",
                version: "1.0.0"
            )
        ]

        let workspace = FileManager.default.temporaryDirectory.path
        if let sessionID = state.createTerminalSession(for: .codex, workingDirectory: workspace) {
            state.removeTerminalSession(sessionID)
        }
        #expect(state.recentlyClosedTerminalSessions.isEmpty == false)

        state.clearRecentlyClosedTerminalSessions()
        #expect(state.recentlyClosedTerminalSessions.isEmpty)
    }
    @Test
    func batchUpdateToolsFiltersToInstalledOnly() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(tool: .codex, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
            ToolInstallation(tool: .claudeCode, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
        ]

        state.batchUpdateTools(Set([.codex, .claudeCode]))

        #expect(state.configOperationStatus == "没有可更新的工具")
        #expect(state.updatingTools.isEmpty)
    }

    @Test
    func batchCheckUpdatesFiltersToInstalledOnly() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(tool: .codex, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
        ]

        state.batchCheckUpdates(Set([.codex]))

        #expect(state.configOperationStatus == "没有可检查更新的工具")
        #expect(state.checkingUpdateTools.isEmpty)
    }

    @Test
    func batchUninstallToolsFiltersToInstalledOnly() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(tool: .codex, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
        ]

        state.batchUninstallTools(Set([.codex]))

        #expect(state.configOperationStatus == "没有可卸载的工具")
    }

    @Test
    func batchUpdateToolsInvokesForEligibleTools() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(tool: .codex, binaryPath: "/usr/bin/env", isInstalled: true, installMethod: .npm, installLocation: "/tmp/codex", version: "1.0.0"),
            ToolInstallation(tool: .claudeCode, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
        ]

        state.batchUpdateTools(Set([.codex, .claudeCode]))

        #expect(state.updatingTools.contains(.codex))
        #expect(!state.updatingTools.contains(.claudeCode))
        #expect(state.configOperationStatus.contains("批量更新 1 个工具"))
    }

    @Test
    func batchCheckUpdatesInvokesForEligibleTools() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.installations = [
            ToolInstallation(tool: .codex, binaryPath: "/usr/bin/env", isInstalled: true, installMethod: .npm, installLocation: "/tmp/codex", version: "1.0.0"),
            ToolInstallation(tool: .claudeCode, binaryPath: nil, isInstalled: false, installMethod: .unknown, installLocation: nil, version: nil),
        ]

        state.batchCheckUpdates(Set([.codex, .claudeCode]))

        #expect(state.checkingUpdateTools.contains(.codex))
        #expect(!state.checkingUpdateTools.contains(.claudeCode))
    }

    @Test
    func toolsWithAvailableUpdatesReturnsCorrectSet() {
        let state = AppState(
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: [])
        )

        state.updateCheckResults[.codex] = ToolUpdateCheckResult(
            state: .updateAvailable,
            localVersion: "1.0.0",
            latestVersion: "2.0.0",
            message: "有更新"
        )
        state.updateCheckResults[.claudeCode] = ToolUpdateCheckResult(
            state: .upToDate,
            localVersion: "1.0.0",
            latestVersion: "1.0.0",
            message: "已是最新"
        )

        let result = state.toolsWithAvailableUpdates

        #expect(result.contains(.codex))
        #expect(!result.contains(.claudeCode))
        #expect(result.count == 1)
    }
}

private func sendRuntimeIPCEvent(socketPath: String, line: String) throws {
    let clientFD = socket(AF_UNIX, SOCK_STREAM, 0)
    guard clientFD >= 0 else {
        throw IPCSendError.socketCreate(errno)
    }
    defer { Darwin.close(clientFD) }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8CString)
    let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= sunPathCapacity else {
        throw IPCSendError.pathTooLong(socketPath)
    }

    withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
        rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
        for (index, byte) in pathBytes.enumerated() {
            rawBuffer[index] = UInt8(bitPattern: byte)
        }
    }

    let addressLength = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + pathBytes.count)
    let connectResult = withUnsafePointer(to: &address) { pointer -> Int32 in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            Darwin.connect(clientFD, sockaddrPointer, addressLength)
        }
    }
    guard connectResult == 0 else {
        throw IPCSendError.connect(errno)
    }

    let payload = line + "\n"
    let bytes = Array(payload.utf8)
    let writeResult = bytes.withUnsafeBytes { rawBuffer -> Int in
        guard let baseAddress = rawBuffer.baseAddress else { return -1 }
        return Darwin.write(clientFD, baseAddress, bytes.count)
    }
    if writeResult < 0 {
        throw IPCSendError.write(errno)
    }
}

private enum IPCSendError: LocalizedError {
    case socketCreate(Int32)
    case connect(Int32)
    case write(Int32)
    case pathTooLong(String)

    var errorDescription: String? {
        switch self {
        case .socketCreate(let code):
            return "IPC client socket 创建失败(errno=\(code))"
        case .connect(let code):
            return "IPC client connect 失败(errno=\(code))"
        case .write(let code):
            return "IPC client write 失败(errno=\(code))"
        case .pathTooLong(let path):
            return "IPC path 过长: \(path)"
        }
    }
}

private final class MockTerminalRunner: CLITerminalRunning {
    var onOutput: ((Data) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onExit: ((Int32) -> Void)?

    private(set) var startedExecutable: String?
    private(set) var startedArguments: [String] = []
    private(set) var startedWorkingDirectory: String = ""
    private(set) var startedEnvironment: [String: String] = [:]
    private(set) var sentInputs: [String] = []
    private(set) var resizeEvents: [(cols: Int, rows: Int)] = []
    private(set) var didTerminate = false

    func start(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws {
        startedExecutable = executable
        startedArguments = arguments
        startedWorkingDirectory = workingDirectory
        startedEnvironment = environment
    }

    func send(data: Data) {
        sentInputs.append(String(decoding: data, as: UTF8.self))
    }

    func resize(cols: Int, rows: Int) {
        resizeEvents.append((cols: cols, rows: rows))
    }

    func terminate() {
        didTerminate = true
    }

    func emitOutput(_ output: String) {
        onOutput?(Data(output.utf8))
    }

    func emitExit(_ exitCode: Int32) {
        onExit?(exitCode)
    }
}

private final class MockRuntimeHintRunner: RuntimeStateHintingTerminalRunner {
    var onOutput: ((Data) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onExit: ((Int32) -> Void)?
    var onRuntimeStateHint: ((TerminalSessionRuntimeState) -> Void)?

    func start(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws {}

    func send(data: Data) {}

    func resize(cols: Int, rows: Int) {}

    func terminate() {}

    func emitRuntimeHint(_ state: TerminalSessionRuntimeState) {
        onRuntimeStateHint?(state)
    }
}

private final class MockRuntimeHintTrackingRunner: RuntimeStateHintingTerminalRunner {
    var onOutput: ((Data) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onExit: ((Int32) -> Void)?
    var onRuntimeStateHint: ((TerminalSessionRuntimeState) -> Void)?

    private(set) var startedExecutable: String?
    private(set) var startedArguments: [String] = []
    private(set) var startedWorkingDirectory: String = ""
    private(set) var startedEnvironment: [String: String] = [:]

    func start(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws {
        startedExecutable = executable
        startedArguments = arguments
        startedWorkingDirectory = workingDirectory
        startedEnvironment = environment
    }

    func send(data _: Data) {}

    func resize(cols _: Int, rows _: Int) {}

    func terminate() {}

    func emitRuntimeHint(_ state: TerminalSessionRuntimeState) {
        onRuntimeStateHint?(state)
    }
}

private final class NotificationSpy: TerminalNotificationServiceProtocol {
    private(set) var didRequestAuthorization = false
    private(set) var notifiedSessionIDs: [UUID] = []

    func requestAuthorizationIfNeeded() {
        didRequestAuthorization = true
    }

    func notifySessionCompleted(_ session: CLITerminalSession) {
        notifiedSessionIDs.append(session.id)
    }
}
