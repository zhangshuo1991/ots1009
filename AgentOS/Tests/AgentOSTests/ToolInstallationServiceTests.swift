import Foundation
import Testing
@testable import AgentOS

struct ToolInstallationServiceTests {
    @Test
    func preferredConfigPathUsesExistingCandidate() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missingPath = root.appendingPathComponent("missing-config", isDirectory: true).path
        let existingPath = root.appendingPathComponent("actual-config", isDirectory: true).path
        try FileManager.default.createDirectory(atPath: existingPath, withIntermediateDirectories: true)

        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { _ in "" }
        )

        let preferred = service.preferredConfigPath(from: [missingPath, existingPath])
        #expect(preferred == existingPath)
    }

    @Test
    func codexConfigDirectoryTargetUsesPrimaryConfigPath() {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { _ in "" }
        )

        let expected = (ProgrammingTool.codex.configPaths.first! as NSString).expandingTildeInPath
        let actual = service.configDirectoryTargetPath(for: .codex)

        #expect(actual == expected)
    }

    @Test
    func claudeConfigDirectoryPrefersNestedSettingsDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fakeHome = root.path
        let legacyFile = URL(fileURLWithPath: fakeHome).appendingPathComponent(".claude.json").path
        let nestedDir = URL(fileURLWithPath: fakeHome).appendingPathComponent(".claude", isDirectory: true)
        let nestedSettings = nestedDir.appendingPathComponent("settings.json").path

        try "{}".write(toFile: legacyFile, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "{}".write(toFile: nestedSettings, atomically: true, encoding: .utf8)

        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { _ in "" }
        )

        let paths = [
            "\(fakeHome)/.claude.json",
            "\(fakeHome)/.claude/settings.json"
        ]

        let picked = service.configDirectoryTargetPath(for: .claudeCode, configPaths: paths)

        #expect(picked == nestedDir.path)
    }

    @Test
    func npmSymlinkResolvesRealInstallLocationAndVersion() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let packageDir = root
            .appendingPathComponent("lib", isDirectory: true)
            .appendingPathComponent("node_modules", isDirectory: true)
            .appendingPathComponent("@openai", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: true)
        let binaryDir = packageDir.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)

        let binaryTarget = binaryDir.appendingPathComponent("codex.js")
        try "#!/usr/bin/env node\nconsole.log('codex');\n"
            .data(using: .utf8)?
            .write(to: binaryTarget)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryTarget.path)

        let packageJSON = packageDir.appendingPathComponent("package.json")
        try "{\"name\":\"@openai/codex\",\"version\":\"1.2.3\"}\n"
            .data(using: .utf8)?
            .write(to: packageJSON)

        let globalBinDir = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: globalBinDir, withIntermediateDirectories: true)
        let binaryLink = globalBinDir.appendingPathComponent("codex")
        try FileManager.default.createSymbolicLink(
            atPath: binaryLink.path,
            withDestinationPath: "../lib/node_modules/@openai/codex/bin/codex.js"
        )

        let detectionService = CLIDetectionService(
            environment: ["PATH": globalBinDir.path],
            commandRunner: { executable, _ in
                if executable == binaryLink.path {
                    return "env: node: No such file or directory\n"
                }
                return ""
            },
            fallbackDirectories: []
        )
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: detectionService,
            shellCommandRunner: { _ in "" }
        )

        let installation = service.detectInstallation(.codex)

        #expect(installation.isInstalled)
        #expect(installation.installMethod == .npm)
        #expect(installation.installLocation == packageDir.path)
        #expect(installation.version == "1.2.3")
    }

    @Test
    func invalidVersionOutputIsIgnored() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let binaryDir = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binaryDir, withIntermediateDirectories: true)
        let binary = binaryDir.appendingPathComponent("codex")
        try "#!/bin/sh\necho codex\n"
            .data(using: .utf8)?
            .write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let detectionService = CLIDetectionService(
            environment: ["PATH": binaryDir.path],
            commandRunner: { executable, _ in
                if executable == binary.path {
                    return "env: node: No such file or directory\n"
                }
                return ""
            },
            fallbackDirectories: []
        )
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: detectionService,
            shellCommandRunner: { _ in "" }
        )

        let installation = service.detectInstallation(.codex)
        #expect(installation.version == nil)
    }

    @Test
    func checkForUpdateReportsAvailableVersionForNpm() async throws {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                if command == "npm view @openai/codex version --json" {
                    return "\"2.1.0\""
                }
                return ""
            }
        )

        let installation = ToolInstallation(
            tool: .codex,
            binaryPath: "/usr/local/bin/codex",
            isInstalled: true,
            installMethod: .npm,
            installLocation: "/usr/local/lib/node_modules/@openai/codex",
            version: "2.0.0"
        )

        let result = try await service.checkForUpdate(installation)
        #expect(result.state == .updateAvailable)
        #expect(result.latestVersion == "2.1.0")
        #expect(result.localVersion == "2.0.0")
    }

    @Test
    func checkForUpdateReportsUpToDateWhenVersionsMatch() async throws {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                if command == "npm view @openai/codex version --json" {
                    return "\"2.1.0\""
                }
                return ""
            }
        )

        let installation = ToolInstallation(
            tool: .codex,
            binaryPath: "/usr/local/bin/codex",
            isInstalled: true,
            installMethod: .npm,
            installLocation: "/usr/local/lib/node_modules/@openai/codex",
            version: "2.1.0"
        )

        let result = try await service.checkForUpdate(installation)
        #expect(result.state == .upToDate)
        #expect(result.latestVersion == "2.1.0")
    }

    @Test
    func checkForUpdateReportsAvailableVersionForPipWithMixedCaseOutput() async throws {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                if command == "python3 -m pip index versions kimi-cli" {
                    return """
                    kimi-cli (1.11.0)
                    Available versions: 1.12.0, 1.11.0, 1.10.0
                    """
                }
                return ""
            }
        )

        let installation = ToolInstallation(
            tool: .kimiCLI,
            binaryPath: "/Users/test/.local/bin/kimi",
            isInstalled: true,
            installMethod: .pip,
            installLocation: "/Users/test/.local/share/uv/tools/kimi-cli/bin",
            version: "1.11.0"
        )

        let result = try await service.checkForUpdate(installation)
        #expect(result.state == .updateAvailable)
        #expect(result.latestVersion == "1.12.0")
        #expect(result.localVersion == "1.11.0")
    }

    @Test
    func checkForUpdateIgnoresNpmErrorPathOutput() async throws {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                if command == "npm view @openai/codex version --json" {
                    return """
                    $ npm view @openai/codex version --json
                    npm error code EEXIST
                    npm error path /Users/zhangshuo/.npm/_cacache/content-v2/sha512/f0/43
                    {
                      "error": {
                        "code": "EEXIST"
                      }
                    }
                    命令执行失败（退出码 1）
                    """
                }
                return ""
            }
        )

        let installation = ToolInstallation(
            tool: .codex,
            binaryPath: "/usr/local/bin/codex",
            isInstalled: true,
            installMethod: .npm,
            installLocation: "/usr/local/lib/node_modules/@openai/codex",
            version: "0.104.0"
        )

        let result = try await service.checkForUpdate(installation)
        #expect(result.state == .unknown)
        #expect(result.latestVersion == nil)
        #expect(result.issue == .npmCachePermission)
        #expect(result.message.contains("一键修复 npm 缓存权限"))
    }

    @Test
    func checkForUpdateDetectsNpmCacheIssueFromPathOnlyOutput() async throws {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                if command == "npm view @google/gemini-cli version --json" {
                    return """
                    $ npm view @google/gemini-cli version --json
                    npm error path /Users/zhangshuo/.npm/_cacache/index-v5/d1/ef/f54103fa39c1c45b3e95f1a0c7eb7d711b6cd3f46a731ad171dc0c41a80c
                    命令执行失败（退出码 1）
                    """
                }
                return ""
            }
        )

        let installation = ToolInstallation(
            tool: .geminiCLI,
            binaryPath: "/usr/local/bin/gemini",
            isInstalled: true,
            installMethod: .npm,
            installLocation: "/usr/local/lib/node_modules/@google/gemini-cli",
            version: "0.28.2"
        )

        let result = try await service.checkForUpdate(installation)
        #expect(result.state == .unknown)
        #expect(result.latestVersion == nil)
        #expect(result.issue == .npmCachePermission)
        #expect(result.message.contains("一键修复 npm 缓存权限"))
    }

    @Test
    func installToolUsesNpmInstallCommand() async throws {
        final class CommandRecorder {
            var commands: [String] = []
        }
        let recorder = CommandRecorder()

        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                recorder.commands.append(command)
                if command == "command -v npm >/dev/null 2>&1 && echo ok" {
                    return "ok"
                }
                if command == "npm install -g @openai/codex" {
                    return "installed"
                }
                return ""
            }
        )

        let output = try await service.installTool(.codex)
        #expect(output == "installed")
        #expect(recorder.commands.contains("command -v npm >/dev/null 2>&1 && echo ok"))
        #expect(recorder.commands.contains("npm install -g @openai/codex"))
    }

    @Test
    func repairNpmCachePermissionsRunsVerifyAfterAdminSuccess() async {
        final class CommandRecorder {
            var userCommands: [String] = []
            var adminCommands: [String] = []
        }
        let recorder = CommandRecorder()

        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                recorder.userCommands.append(command)
                if command == "npm cache clean --force && npm cache verify" {
                    return "$ \(command)\n命令执行完成（退出码 0）"
                }
                return ""
            },
            adminShellCommandRunner: { command in
                recorder.adminCommands.append(command)
                return "$ \(command)\n命令执行完成（退出码 0）"
            }
        )

        let output = await service.repairNpmCachePermissions()
        #expect(recorder.adminCommands.count == 1)
        #expect(recorder.userCommands.contains("npm cache clean --force && npm cache verify"))
        #expect(output.contains("npm cache verify"))
    }

    @Test
    func repairNpmCachePermissionsStopsWhenAdminFails() async {
        final class CommandRecorder {
            var userCommands: [String] = []
            var adminCommands: [String] = []
        }
        let recorder = CommandRecorder()

        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { command in
                recorder.userCommands.append(command)
                return ""
            },
            adminShellCommandRunner: { command in
                recorder.adminCommands.append(command)
                return "$ \(command)\n命令执行失败（退出码 1）"
            }
        )

        let output = await service.repairNpmCachePermissions()
        #expect(recorder.adminCommands.count == 1)
        #expect(recorder.userCommands.isEmpty)
        #expect(output.contains("命令执行失败（退出码 1）"))
    }

    @Test
    func installToolForDirectOnlyToolThrows() async {
        let service = ToolInstallationService(
            fileManager: .default,
            detectionService: CLIDetectionService(environment: ["PATH": ""], commandRunner: { _, _ in "" }, fallbackDirectories: []),
            shellCommandRunner: { _ in "" }
        )

        do {
            _ = try await service.installTool(.cursor)
            Issue.record("Expected cursor install to throw unsupported operation")
        } catch {
            #expect(error.localizedDescription.contains("官网安装"))
        }
    }
}
