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

enum ToolUpdateState: String, Codable {
    case upToDate
    case updateAvailable
    case unknown
}

enum ToolUpdateIssue: String, Codable, Equatable {
    case npmCachePermission
}

struct ToolUpdateCheckResult: Codable, Equatable {
    let state: ToolUpdateState
    let localVersion: String?
    let latestVersion: String?
    let message: String
    let issue: ToolUpdateIssue?

    init(
        state: ToolUpdateState,
        localVersion: String?,
        latestVersion: String?,
        message: String,
        issue: ToolUpdateIssue? = nil
    ) {
        self.state = state
        self.localVersion = localVersion
        self.latestVersion = latestVersion
        self.message = message
        self.issue = issue
    }

    var hasUpdate: Bool {
        state == .updateAvailable
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
    case githubCopilotCLI
    case aider
    case goose
    case plandex
    case openHands
    case continueCLI
    case amp
    case kiro
    case cody
    case qwenCode

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
        case .githubCopilotCLI:
            return "GitHub Copilot CLI"
        case .aider:
            return "Aider"
        case .goose:
            return "Goose"
        case .plandex:
            return "Plandex"
        case .openHands:
            return "OpenHands CLI"
        case .continueCLI:
            return "Continue CLI"
        case .amp:
            return "Amp CLI"
        case .kiro:
            return "Kiro CLI"
        case .cody:
            return "Cody CLI"
        case .qwenCode:
            return "Qwen Code"
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
        case .githubCopilotCLI:
            return ["copilot", "github-copilot"]
        case .aider:
            return ["aider"]
        case .goose:
            return ["goose"]
        case .plandex:
            return ["plandex", "pdx"]
        case .openHands:
            return ["openhands"]
        case .continueCLI:
            return ["cn", "continue"]
        case .amp:
            return ["amp"]
        case .kiro:
            return ["kiro"]
        case .cody:
            return ["cody"]
        case .qwenCode:
            return ["qwen", "qwen-code"]
        }
    }

    var configPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex:
            return ["\(home)/.config/codex", "\(home)/.codex"]
        case .claudeCode:
            return ["\(home)/.claude.json", "\(home)/.claude/settings.json"]
        case .kimiCLI:
            return ["\(home)/.claude/kimi", "\(home)/.config/kimi"]
        case .opencode:
            return ["\(home)/.opencode", "\(home)/.config/opencode"]
        case .geminiCLI:
            return ["\(home)/.gemini", "\(home)/.config/gemini"]
        case .cursor:
            return ["\(home)/Library/Application Support/Cursor/User"]
        case .windsurf:
            return ["\(home)/Library/Application Support/Windsurf/User"]
        case .trae:
            return ["\(home)/.config/trae"]
        case .kiloCode:
            return ["\(home)/.config/kilocode"]
        case .openclaw:
            return ["\(home)/.config/openclaw"]
        case .cline:
            return ["\(home)/.cline", "\(home)/.config/cline"]
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
        case .githubCopilotCLI:
            return ["\(home)/.copilot", "\(home)/.copilot/lsp-config.json"]
        case .aider:
            return ["\(home)/.aider.conf.yml", "\(home)/.config/aider"]
        case .goose:
            return ["\(home)/.config/goose/config.yaml", "\(home)/.config/goose/secrets.yaml"]
        case .plandex:
            return ["\(home)/.plandex", "\(home)/.config/plandex"]
        case .openHands:
            return ["\(home)/.openhands/settings.json", "\(home)/.openhands/conversations"]
        case .continueCLI:
            return ["\(home)/.continue/config.yaml", "\(home)/.continue/permissions.yaml"]
        case .amp:
            return ["\(home)/.config/amp", "\(home)/.config/amp/AGENTS.md"]
        case .kiro:
            return ["\(home)/.kiro", "\(home)/.config/kiro"]
        case .cody:
            return ["\(home)/.config/sourcegraph", "\(home)/.config/cody"]
        case .qwenCode:
            return ["\(home)/.qwen/settings.json", "\(home)/.qwen"]
        }
    }

    var npmPackageName: String? {
        switch self {
        case .codex:
            return "@openai/codex"
        case .claudeCode:
            return "@anthropic-ai/claude-code"
        case .kimiCLI:
            return "kimi-cli"
        case .opencode:
            return "opencode-ai"
        case .geminiCLI:
            return "@google/gemini-cli"
        case .cline:
            return "cline"
        case .rooCode:
            return "roo-code"
        case .grokCLI:
            return "grok-cli"
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
        case .droid:
            return nil
        case .zed:
            return nil
        case .monkeyCode:
            return nil
        case .githubCopilotCLI:
            return "@github/copilot"
        case .aider:
            return nil
        case .goose:
            return nil
        case .plandex:
            return nil
        case .openHands:
            return nil
        case .continueCLI:
            return "@continuedev/cli"
        case .amp:
            return "@sourcegraph/amp"
        case .kiro:
            return nil
        case .cody:
            return "@sourcegraph/cody"
        case .qwenCode:
            return "@qwen-code/qwen-code"
        }
    }

    var pipPackageName: String? {
        switch self {
        case .kimiCLI:
            return "kimi-cli"
        case .openclaw:
            return "openclaw"
        case .aider:
            return "aider-chat"
        case .openHands:
            return "openhands"
        default:
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
        case .githubCopilotCLI:
            return "copilot-cli"
        case .aider:
            return nil
        case .goose:
            return nil
        case .plandex:
            return nil
        case .openHands:
            return nil
        case .continueCLI:
            return nil
        case .amp:
            return nil
        case .kiro:
            return nil
        case .cody:
            return nil
        case .qwenCode:
            return "qwen-code"
        }
    }

    var officialInstallURL: String? {
        switch self {
        case .cursor:
            return "https://cursor.com/downloads"
        case .windsurf:
            return "https://windsurf.com/editor"
        case .trae:
            return "https://www.trae.ai/"
        case .droid:
            return "https://droid.dev"
        case .monkeyCode:
            return "https://monkeycode.ai"
        case .githubCopilotCLI:
            return "https://github.com/github/copilot-cli#installation"
        case .aider:
            return "https://aider.chat/docs/install.html"
        case .goose:
            return "https://block.github.io/goose/docs/getting-started/installation/"
        case .plandex:
            return "https://plandex.ai/"
        case .openHands:
            return "https://docs.openhands.dev/openhands/usage/cli/installation"
        case .continueCLI:
            return "https://docs.continue.dev/guides/cli"
        case .amp:
            return "https://ampcode.com/manual"
        case .kiro:
            return "https://kiro.dev/cli/"
        case .cody:
            return "https://sourcegraph.com/docs/cody/clients/install-cli"
        case .qwenCode:
            return "https://github.com/QwenLM/qwen-code#installation"
        default:
            return nil
        }
    }

    var officialWebsiteURL: String? {
        switch self {
        case .codex:
            return "https://openai.com/codex/"
        case .claudeCode:
            return "https://www.anthropic.com/claude-code"
        case .kimiCLI:
            return "https://www.kimi.com/code/en"
        case .opencode:
            return "https://opencode.ai/"
        case .geminiCLI:
            return "https://geminicli.com/"
        case .cursor:
            return "https://cursor.com/"
        case .windsurf:
            return "https://windsurf.com/editor"
        case .trae:
            return "https://www.trae.ai/"
        case .kiloCode:
            return "https://kilocode.ai/"
        case .openclaw:
            return "https://openclaw.ai/"
        case .cline:
            return "https://github.com/cline/cline"
        case .rooCode:
            return "https://roocode.com/"
        case .grokCLI:
            return "https://grokcli.dev/"
        case .droid:
            return "https://droid.dev/"
        case .zed:
            return "https://zed.dev/"
        case .monkeyCode:
            return "https://monkeycode.ai/"
        case .githubCopilotCLI:
            return "https://github.com/features/copilot"
        case .aider:
            return "https://aider.chat/"
        case .goose:
            return "https://block.github.io/goose/"
        case .plandex:
            return "https://plandex.ai/"
        case .openHands:
            return "https://www.all-hands.dev/"
        case .continueCLI:
            return "https://www.continue.dev/"
        case .amp:
            return "https://ampcode.com/"
        case .kiro:
            return "https://kiro.dev/"
        case .cody:
            return "https://sourcegraph.com/cody"
        case .qwenCode:
            return "https://github.com/QwenLM/qwen-code"
        }
    }

    var officialDocumentationURL: String? {
        switch self {
        case .codex:
            return "https://developers.openai.com/codex/"
        case .claudeCode:
            return "https://docs.anthropic.com/en/docs/claude-code/overview"
        case .kimiCLI:
            return "https://www.kimi.com/code/docs/en/"
        case .opencode:
            return "https://opencode.ai/docs"
        case .geminiCLI:
            return "https://geminicli.com/docs/"
        case .cursor:
            return "https://docs.cursor.com/"
        case .windsurf:
            return "https://docs.windsurf.com/"
        case .kiloCode:
            return "https://kilocode.ai/docs"
        case .openclaw:
            return "https://docs.openclaw.ai/getting-started"
        case .cline:
            return "https://docs.cline.bot/"
        case .rooCode:
            return "https://docs.roocode.com/"
        case .zed:
            return "https://zed.dev/docs/"
        case .githubCopilotCLI:
            return "https://github.com/github/copilot-cli#readme"
        case .aider:
            return "https://aider.chat/docs/"
        case .goose:
            return "https://block.github.io/goose/docs/"
        case .plandex:
            return "https://docs.plandex.ai/"
        case .openHands:
            return "https://docs.openhands.dev/openhands/usage/cli/installation"
        case .continueCLI:
            return "https://docs.continue.dev/guides/cli"
        case .amp:
            return "https://ampcode.com/manual"
        case .kiro:
            return "https://kiro.dev/cli/"
        case .cody:
            return "https://sourcegraph.com/docs/cody/clients/install-cli"
        case .qwenCode:
            return "https://qwen.readthedocs.io/en/latest/tools/qwen-code.html"
        default:
            return officialWebsiteURL
        }
    }

    var officialCommunityURL: String? {
        switch self {
        case .codex:
            return "https://community.openai.com/"
        case .claudeCode:
            return "https://support.anthropic.com/en/"
        case .opencode:
            return "https://github.com/anomalyco/opencode"
        case .geminiCLI:
            return "https://github.com/google-gemini/gemini-cli/issues"
        case .cursor:
            return "https://forum.cursor.com/"
        case .windsurf:
            return "https://windsurf.canny.io/feature-requests"
        case .kiloCode:
            return "https://github.com/Kilo-Org/kilocode/discussions"
        case .openclaw:
            return "https://github.com/openclaw/openclaw#community"
        case .cline:
            return "https://github.com/cline/cline/discussions"
        case .rooCode:
            return "https://github.com/RooCodeInc/Roo-Code/issues"
        case .zed:
            return "https://github.com/zed-industries/zed/discussions"
        case .githubCopilotCLI:
            return "https://github.com/orgs/community/discussions/categories/copilot"
        case .aider:
            return "https://github.com/Aider-AI/aider/discussions"
        case .goose:
            return "https://github.com/block/goose/discussions"
        case .plandex:
            return "https://github.com/plandex-ai/plandex"
        case .openHands:
            return "https://github.com/All-Hands-AI/OpenHands/discussions"
        case .continueCLI:
            return "https://github.com/continuedev/continue/discussions"
        case .amp:
            return "https://community.sourcegraph.com/"
        case .kiro:
            return "https://kiro.dev/"
        case .cody:
            return "https://community.sourcegraph.com/"
        case .qwenCode:
            return "https://github.com/QwenLM/qwen-code/discussions"
        default:
            return officialWebsiteURL
        }
    }

    var preferredInstallMethods: [InstallMethod] {
        var methods: [InstallMethod] = []

        if npmPackageName != nil {
            methods.append(.npm)
        }
        if homebrewFormula != nil {
            methods.append(.homebrew)
        }
        if pipPackageName != nil {
            methods.append(.pip)
        }
        if officialInstallURL != nil {
            methods.append(.direct)
        }

        return methods.isEmpty ? [.unknown] : methods
    }

    func packageName(for method: InstallMethod) -> String? {
        switch method {
        case .npm:
            return npmPackageName
        case .homebrew:
            return homebrewFormula
        case .pip:
            return pipPackageName
        default:
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
        case .githubCopilotCLI:
            return "安装后确保 copilot 可执行。"
        case .aider:
            return "安装后确保 aider 可执行。"
        case .goose:
            return "安装后确保 goose 可执行。"
        case .plandex:
            return "安装后确保 plandex 或 pdx 可执行。"
        case .openHands:
            return "安装后确保 openhands 可执行。"
        case .continueCLI:
            return "安装后确保 cn 可执行。"
        case .amp:
            return "安装后确保 amp 可执行。"
        case .kiro:
            return "安装后确保 kiro 可执行。"
        case .cody:
            return "安装后确保 cody 可执行。"
        case .qwenCode:
            return "安装后确保 qwen 或 qwen-code 可执行。"
        }
    }

    var versionArguments: [[String]] {
        [["--version"], ["-v"], ["version"]]
    }

    var supportsIntegratedTerminal: Bool {
        true
    }

    var integratedTerminalArguments: [String] {
        switch self {
        case .codex, .claudeCode, .qwenCode:
            return []
        default:
            return []
        }
    }

    var supportsDirectConfigEditing: Bool {
        switch self {
        case .codex, .claudeCode:
            return true
        default:
            return false
        }
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
