import Foundation

enum CLITool: String, CaseIterable, Codable, Hashable, Identifiable {
    case codex
    case claudeCode
    case opencode
    case geminiCLI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex CLI"
        case .claudeCode: return "Claude Code"
        case .opencode: return "OpenCode"
        case .geminiCLI: return "Gemini CLI"
        }
    }

    var binaryCandidates: [String] {
        switch self {
        case .codex:
            return ["codex"]
        case .claudeCode:
            return ["claude-code", "claude"]
        case .opencode:
            return ["opencode"]
        case .geminiCLI:
            return ["gemini", "gemini-cli"]
        }
    }

    var installGuide: String {
        switch self {
        case .codex:
            return "参考官方文档安装 Codex CLI，并确保 `codex` 在 PATH 中可执行。"
        case .claudeCode:
            return "参考官方文档安装 Claude Code，并确保 `claude-code` 或 `claude` 在 PATH 中。"
        case .opencode:
            return "安装 OpenCode CLI，并确保 `opencode` 可执行。"
        case .geminiCLI:
            return "安装 Gemini CLI，并确保 `gemini` 或 `gemini-cli` 可执行。"
        }
    }
}

struct CLIToolStatus: Codable, Hashable, Identifiable {
    var id: CLITool { tool }
    var tool: CLITool
    var isInstalled: Bool
    var resolvedBinary: String?
    var version: String?
    var guidance: String
}

struct CLIIntegrationService {
    func detectAll() -> [CLIToolStatus] {
        CLITool.allCases.map(detect)
    }

    func detect(_ tool: CLITool) -> CLIToolStatus {
        for binary in tool.binaryCandidates {
            if let path = which(binary) {
                return CLIToolStatus(
                    tool: tool,
                    isInstalled: true,
                    resolvedBinary: path,
                    version: version(of: path),
                    guidance: "已检测到可执行文件，建议在命令模板中使用该命令。"
                )
            }
        }

        return CLIToolStatus(
            tool: tool,
            isInstalled: false,
            resolvedBinary: nil,
            version: nil,
            guidance: tool.installGuide
        )
    }

    private func which(_ binary: String) -> String? {
        run("/usr/bin/which", args: [binary]).trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private func version(of binaryPath: String) -> String? {
        let output = run(binaryPath, args: ["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }
        return output.components(separatedBy: .newlines).first
    }

    private func run(_ executable: String, args: [String]) -> String {
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

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
