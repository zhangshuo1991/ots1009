import Foundation

enum DetectionSource: String, Codable {
    case pathScan
    case zshLoginShell
    case bashLoginShell
    case unknown

    var title: String {
        switch self {
        case .pathScan:
            return "PATH 扫描"
        case .zshLoginShell:
            return "zsh 登录 shell"
        case .bashLoginShell:
            return "bash 登录 shell"
        case .unknown:
            return "未知来源"
        }
    }
}

enum InstallMethod: String, CaseIterable, Identifiable, Codable {
    case npm
    case homebrew
    case pip
    case direct
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .npm: return "npm"
        case .homebrew: return "Homebrew"
        case .pip: return "pip"
        case .direct: return "Direct Download"
        case .unknown: return "Unknown"
        }
    }

    var updateCommand: String? {
        switch self {
        case .npm: return "npm update -g"
        case .homebrew: return "brew upgrade"
        case .pip: return "pip install --upgrade"
        default: return nil
        }
    }

    var uninstallCommand: String? {
        switch self {
        case .npm: return "npm uninstall -g"
        case .homebrew: return "brew uninstall"
        case .pip: return "pip uninstall"
        default: return nil
        }
    }
}

enum ProgrammingTool: String, CaseIterable, Identifiable, Codable {
    case codex
    case claudeCode
    case kimiCLI
    case opencode
    case geminiCLI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex:
            return "Codex"
        case .claudeCode:
            return "Claude Code"
        case .kimiCLI:
            return "Kimi CLI"
        case .opencode:
            return "OpenCode"
        case .geminiCLI:
            return "Gemini CLI"
        }
    }

    var candidates: [String] {
        switch self {
        case .codex:
            return ["codex"]
        case .claudeCode:
            return ["claude", "claude-code"]
        case .kimiCLI:
            return ["kimi", "kimi-cli", "kimicli"]
        case .opencode:
            return ["opencode"]
        case .geminiCLI:
            return ["gemini", "gemini-cli"]
        }
    }

    var installHint: String {
        switch self {
        case .codex:
            return "安装后确保 codex 可执行。"
        case .claudeCode:
            return "安装后确保 claude 或 claude-code 可执行。"
        case .kimiCLI:
            return "安装后确保 kimi 或 kimi-cli 可执行。"
        case .opencode:
            return "安装后确保 opencode 可执行。"
        case .geminiCLI:
            return "安装后确保 gemini 或 gemini-cli 可执行。"
        }
    }

    var versionArguments: [[String]] {
        [["--version"], ["-v"], ["version"]]
    }
}

struct ToolDetectionStatus: Identifiable, Hashable, Codable {
    let id: ProgrammingTool
    let tool: ProgrammingTool
    let isInstalled: Bool
    let binaryPath: String?
    let version: String?
    let source: DetectionSource
    let note: String
}
