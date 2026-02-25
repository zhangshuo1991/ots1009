import Foundation
import Testing
@testable import AgentOS

struct CLIDetectionServiceTests {
    @Test
    func detectFromExplicitPathScan() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let binaryURL = root.appendingPathComponent("codex")
        let script = "#!/bin/sh\necho codex-test-1.0\n"
        try script.data(using: .utf8)?.write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let service = CLIDetectionService(
            environment: ["PATH": root.path],
            commandRunner: { executable, args in
                CLIDetectionServiceTests.run(executable: executable, args: args)
            },
            fallbackDirectories: []
        )

        let status = service.detect(.codex)
        #expect(status.isInstalled)
        #expect(status.binaryPath == binaryURL.path)
        #expect(status.source == .pathScan)
    }

    @Test
    func detectUsesLoginShellFallback() {
        let service = CLIDetectionService(
            environment: ["PATH": "/no-bin"],
            commandRunner: { executable, args in
                if executable == "/bin/zsh", args.joined(separator: " ").contains("command -v codex") {
                    return "/mock/bin/codex\n"
                }
                if executable == "/mock/bin/codex", args == ["--version"] {
                    return "codex mock 9.9.9\n"
                }
                return ""
            },
            fallbackDirectories: []
        )

        let status = service.detect(.codex)
        #expect(status.isInstalled)
        #expect(status.binaryPath == "/mock/bin/codex")
        #expect(status.source == .zshLoginShell)
        #expect(status.version == "codex mock 9.9.9")
    }

    @Test
    func detectNotInstalledWhenNoCandidateFound() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = CLIDetectionService(
            environment: ["PATH": "/empty"],
            commandRunner: { _, _ in "" },
            homeDirectory: root.path,
            fallbackDirectories: []
        )

        let status = service.detect(.kimiCLI)
        #expect(!status.isInstalled)
        #expect(status.binaryPath == nil)
    }

    @Test
    func detectFromUVToolDirectoryWhenPathIsEmpty() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let uvToolBinDirectory = root
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("uv", isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true)
            .appendingPathComponent("kimi-cli", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: uvToolBinDirectory, withIntermediateDirectories: true)

        let binaryURL = uvToolBinDirectory.appendingPathComponent("kimi")
        try "#!/bin/sh\necho kimi-cli 1.12.0\n"
            .data(using: .utf8)?
            .write(to: binaryURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)

        let service = CLIDetectionService(
            environment: ["PATH": ""],
            commandRunner: { executable, args in
                CLIDetectionServiceTests.run(executable: executable, args: args)
            },
            homeDirectory: root.path,
            fallbackDirectories: []
        )

        let status = service.detect(.kimiCLI)
        #expect(status.isInstalled)
        #expect(status.binaryPath == binaryURL.path)
        #expect(status.source == .pathScan)
    }

    private static func run(executable: String, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }
}
