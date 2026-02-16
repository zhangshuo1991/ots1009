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
        case .direct: return "直接下载"
        case .unknown: return "未知"
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
    case cursor
    case windsurf
    case trae
    case kiloCode
    case openclaw
    case cline
    case rooCode
    case grokCLI
    case droid
    case zed
    case monkeyCode

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
        case .cursor:
            return "Cursor"
        case .windsurf:
            return "Windsurf"
        case .trae:
            return "Trae"
        case .kiloCode:
            return "KiloCode"
        case .openclaw:
            return "OpenClaw"
        case .cline:
            return "Cline"
        case .rooCode:
            return "RooCode"
        case .grokCLI:
            return "Grok CLI"
        case .droid:
            return "Droid"
        case .zed:
            return "Zed"
        case .monkeyCode:
            return "MonkeyCode"
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
        case .cursor:
            return ["cursor"]
        case .windsurf:
            return ["windsurf"]
        case .trae:
            return ["trae"]
        case .kiloCode:
            return ["kilocode", "kilo-code", "kilocode"]
        case .openclaw:
            return ["openclaw"]
        case .cline:
            return ["cline"]
        case .rooCode:
            return ["roocode", "roo-code"]
        case .grokCLI:
            return ["grok", "grok-cli"]
        case .droid:
            return ["droid"]
        case .zed:
            return ["zed"]
        case .monkeyCode:
            return ["monkeycode", "monkey-code"]
        }
    }

    var configPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex:
            return ["\(home)/.config/codex"]
        case .claudeCode:
            return ["\(home)/.config/claude"]
        case .kimiCLI:
            return ["\(home)/.config/kimi"]
        case .opencode:
            return ["\(home)/.config/opencode"]
        case .geminiCLI:
            return ["\(home)/.config/gemini"]
        case .cursor:
            return ["\(home)/Library/Application Support/Cursor"]
        case .windsurf:
            return ["\(home)/Library/Application Support/Windsurf"]
        case .trae:
            return ["\(home)/.config/trae"]
        case .kiloCode:
            return ["\(home)/.config/kilocode"]
        case .openclaw:
            return ["\(home)/.config/openclaw"]
        case .cline:
            return ["\(home)/.config/cline"]
        case .rooCode:
            return ["\(home)/.config/roocode"]
        case .grokCLI:
            return ["\(home)/.config/grok"]
        case .droid:
            return ["\(home)/.config/droid"]
        case .zed:
            return ["\(home)/.config/zed"]
        case .monkeyCode:
            return ["\(home)/.config/monkeycode"]
        }
    }

    var npmPackageName: String? {
        switch self {
        case .codex:
            return "@anthropic-ai/codex"
        case .claudeCode:
            return "@anthropic-ai/claude-code"
        case .kimiCLI:
            return "kimi-cli"
        case .opencode:
            return "opencode"
        case .geminiCLI:
            return "@anthropic-ai/gemini-cli"
        case .cursor:
            return nil
        case .windsurf:
            return nil
        case .trae:
            return nil
        case .kiloCode:
            return nil
        case .openclaw:
            return nil
        case .cline:
            return nil
        case .rooCode:
            return nil
        case .grokCLI:
            return nil
        case .droid:
            return nil
        case .zed:
            return nil
        case .monkeyCode:
            return nil
        }
    }

    var homebrewFormula: String? {
        switch self {
        case .codex:
            return nil
        case .claudeCode:
            return nil
        case .kimiCLI:
            return nil
        case .opencode:
            return nil
        case .geminiCLI:
            return nil
        case .cursor:
            return nil
        case .windsurf:
            return nil
        case .trae:
            return nil
        case .kiloCode:
            return nil
        case .openclaw:
            return nil
        case .cline:
            return "cline"
        case .rooCode:
            return nil
        case .grokCLI:
            return nil
        case .droid:
            return nil
        case .zed:
            return "zed"
        case .monkeyCode:
            return nil
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
        case .cursor:
            return "安装后确保 cursor 可执行。"
        case .windsurf:
            return "安装后确保 windsurf 可执行。"
        case .trae:
            return "安装后确保 trae 可执行。"
        case .kiloCode:
            return "安装后确保 kilocode 或 kilo-code 可执行。"
        case .openclaw:
            return "安装后确保 openclaw 可执行。"
        case .cline:
            return "安装后确保 cline 可执行。"
        case .rooCode:
            return "安装后确保 roocode 或 roo-code 可执行。"
        case .grokCLI:
            return "安装后确保 grok 或 grok-cli 可执行。"
        case .droid:
            return "安装后确保 droid 可执行。"
        case .zed:
            return "安装后确保 zed 可执行。"
        case .monkeyCode:
            return "安装后确保 monkeycode 或 monkey-code 可执行。"
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

struct ToolInstallation: Identifiable, Codable {
    let id: ProgrammingTool
    let tool: ProgrammingTool
    var binaryPath: String?
    var isInstalled: Bool
    var installMethod: InstallMethod
    var installLocation: String?
    var configPaths: [String]
    var version: String?

    init(
        tool: ProgrammingTool,
        binaryPath: String? = nil,
        isInstalled: Bool = false,
        installMethod: InstallMethod = .unknown,
        installLocation: String? = nil,
        configPaths: [String]? = nil,
        version: String? = nil
    ) {
        self.id = tool
        self.tool = tool
        self.binaryPath = binaryPath
        self.isInstalled = isInstalled
        self.installMethod = installMethod
        self.installLocation = installLocation
        self.configPaths = configPaths ?? tool.configPaths
        self.version = version
    }
}

struct ToolConfig: Codable {
    var apiKey: String
    var httpProxy: String
    var httpsProxy: String
    var model: String

    init(
        apiKey: String = "",
        httpProxy: String = "",
        httpsProxy: String = "",
        model: String = ""
    ) {
        self.apiKey = apiKey
        self.httpProxy = httpProxy
        self.httpsProxy = httpsProxy
        self.model = model
    }
}
