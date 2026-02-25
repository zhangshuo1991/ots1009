import Foundation

enum ToolEditableFieldID {
    static let apiKey = "api_key"
    static let baseURL = "base_url"
    static let model = "model"
    static let fallbackModel = "fallback_model"
    static let provider = "provider"
    static let workspaceRoot = "workspace_root"
    static let googleCloudProject = "google_cloud_project"
    static let googleCloudLocation = "google_cloud_location"
}

struct ToolEditableFieldDescriptor: Identifiable, Hashable {
    let id: String
    let label: String
    let placeholder: String
    let helper: String
    let isSecure: Bool
    let primaryKey: String
    let canonicalKey: String
    let readKeys: [String]
}

struct ToolDetailProfile {
    let roleTitle: String
    let roleSubtitle: String
    let capabilityTags: [String]
    let diagnostics: [String]
    let editableFields: [ToolEditableFieldDescriptor]
}

enum ToolDetailProfileFactory {
    static func profile(for tool: ProgrammingTool) -> ToolDetailProfile {
        switch tool {
        case .codex:
            return ToolDetailProfile(
                roleTitle: "OpenAI Codex",
                roleSubtitle: "官方定位为“一个可在你所有编码场景使用的 Agent”，覆盖终端、IDE 与云端任务。",
                capabilityTags: ["OpenAI", "Agent", "终端/IDE/云端"],
                diagnostics: [
                    "优先检查 ~/.codex/config.toml 与 auth.json 是否同时存在。",
                    "若自定义 OPENAI_BASE_URL，请确认模型权限与账号一致。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "OpenAI API Key",
                        placeholder: "sk-...",
                        helper: "写入 OPENAI_API_KEY",
                        primaryKey: "OPENAI_API_KEY"
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "OpenAI Base URL",
                        placeholder: "https://api.openai.com/v1",
                        helper: "写入 OPENAI_BASE_URL",
                        primaryKey: "OPENAI_BASE_URL"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "gpt-5-codex",
                        helper: "写入 OPENAI_MODEL / CODEX_MODEL",
                        primaryKey: "OPENAI_MODEL"
                    ),
                ]
            )
        case .claudeCode:
            return ToolDetailProfile(
                roleTitle: "Anthropic Claude Code",
                roleSubtitle: "Anthropic 官方 Agent 编程工具，可读代码库、改文件、跑命令，并在终端/IDE/桌面/浏览器可用。",
                capabilityTags: ["Anthropic", "Agent", "终端/IDE"],
                diagnostics: [
                    "优先检查 ~/.claude/settings.json 中 env 段落。",
                    "若使用代理地址，确认 ANTHROPIC_BASE_URL 与模型匹配。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Anthropic Token",
                        placeholder: "sk-ant-...",
                        helper: "写入 ANTHROPIC_AUTH_TOKEN",
                        primaryKey: "ANTHROPIC_AUTH_TOKEN",
                        readKeys: ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "Anthropic Base URL",
                        placeholder: "https://api.anthropic.com",
                        helper: "写入 ANTHROPIC_BASE_URL",
                        primaryKey: "ANTHROPIC_BASE_URL"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "写入 ANTHROPIC_MODEL",
                        primaryKey: "ANTHROPIC_MODEL"
                    ),
                ]
            )
        case .kimiCLI:
            return ToolDetailProfile(
                roleTitle: "Kimi Code CLI",
                roleSubtitle: "Kimi Code 官方定位 Next-Gen AI Code Agent，提供高性能 CLI 自动化编程。",
                capabilityTags: ["Moonshot", "AI Code Agent", "CLI"],
                diagnostics: [
                    "如果使用 OPENAI_BASE_URL，模型前缀需与 Kimi 兼容。",
                    "检查本地代理是否影响 Moonshot 连接。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Moonshot API Key",
                        placeholder: "sk-...",
                        helper: "写入 MOONSHOT_API_KEY",
                        primaryKey: "MOONSHOT_API_KEY",
                        readKeys: ["MOONSHOT_API_KEY", "KIMI_API_KEY", "OPENAI_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "Moonshot Base URL",
                        placeholder: "https://api.moonshot.cn/v1",
                        helper: "写入 MOONSHOT_BASE_URL",
                        primaryKey: "MOONSHOT_BASE_URL",
                        readKeys: ["MOONSHOT_BASE_URL", "OPENAI_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "kimi-k2",
                        helper: "写入 KIMI_MODEL",
                        primaryKey: "KIMI_MODEL"
                    ),
                ]
            )
        case .opencode:
            return ToolDetailProfile(
                roleTitle: "OpenCode 开源代码 Agent",
                roleSubtitle: "官方定位为开源 coding agent，可在终端工作并接入多模型提供商。",
                capabilityTags: ["开源", "Coding Agent", "多模型"],
                diagnostics: [
                    "确认主模型与回退模型均可访问，避免运行期漂移。",
                    "路由地址建议固定到单一网关。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "路由 API Key",
                        placeholder: "sk-or-...",
                        helper: "写入 OPENCODE_API_KEY",
                        primaryKey: "OPENCODE_API_KEY",
                        readKeys: ["OPENCODE_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "路由 Base URL",
                        placeholder: "https://openrouter.ai/api/v1",
                        helper: "写入 OPENROUTER_BASE_URL",
                        primaryKey: "OPENROUTER_BASE_URL",
                        readKeys: ["OPENROUTER_BASE_URL", "OPENAI_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "主模型",
                        placeholder: "openai/gpt-5",
                        helper: "写入 OPENCODE_MODEL",
                        primaryKey: "OPENCODE_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.fallbackModel,
                        label: "回退模型",
                        placeholder: "anthropic/claude-3-7-sonnet",
                        helper: "写入 OPENCODE_FALLBACK_MODEL",
                        primaryKey: "OPENCODE_FALLBACK_MODEL"
                    ),
                ]
            )
        case .geminiCLI:
            return ToolDetailProfile(
                roleTitle: "Google Gemini CLI",
                roleSubtitle: "Google 开源终端 Agent，把 Gemini 能力直接带到命令行，并内置搜索/文件/shell 工具。",
                capabilityTags: ["Google", "开源", "终端 Agent"],
                diagnostics: [
                    "Vertex 模式必须同时配置 project 与 location。",
                    "npm 安装失败优先检查 ~/.npm 缓存权限。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Gemini API Key",
                        placeholder: "AIza...",
                        helper: "写入 GEMINI_API_KEY",
                        primaryKey: "GEMINI_API_KEY",
                        readKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.googleCloudProject,
                        label: "Google Cloud Project",
                        placeholder: "my-gcp-project",
                        helper: "写入 GOOGLE_CLOUD_PROJECT",
                        primaryKey: "GOOGLE_CLOUD_PROJECT"
                    ),
                    textField(
                        id: ToolEditableFieldID.googleCloudLocation,
                        label: "Google Cloud Location",
                        placeholder: "us-central1",
                        helper: "写入 GOOGLE_CLOUD_LOCATION",
                        primaryKey: "GOOGLE_CLOUD_LOCATION"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "gemini-2.5-pro",
                        helper: "写入 GEMINI_MODEL",
                        primaryKey: "GEMINI_MODEL"
                    ),
                ]
            )
        case .cursor:
            return ToolDetailProfile(
                roleTitle: "Cursor AI 编辑器",
                roleSubtitle: "官方定位“the best way to code with AI”，强调在编辑器内高效构建软件。",
                capabilityTags: ["AI 编辑器", "代码库理解", "高效开发"],
                diagnostics: [
                    "确保 User 目录可写，防止设置无法落盘。",
                    "客户端登录态优先于本地桥接 key。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "桥接 API Key",
                        placeholder: "可选：用于外部 provider",
                        helper: "写入 CURSOR_API_KEY",
                        primaryKey: "CURSOR_API_KEY"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型偏好",
                        placeholder: "gpt-5-codex",
                        helper: "写入 CURSOR_MODEL",
                        primaryKey: "CURSOR_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.workspaceRoot,
                        label: "工作区根目录",
                        placeholder: "/Users/zhangshuo/workspace",
                        helper: "写入 CURSOR_WORKSPACE_ROOT",
                        primaryKey: "CURSOR_WORKSPACE_ROOT"
                    ),
                ]
            )
        case .windsurf:
            return ToolDetailProfile(
                roleTitle: "Windsurf Editor",
                roleSubtitle: "官方定位“AI agent-powered IDE”，目标是让开发者保持 flow 持续编码。",
                capabilityTags: ["AI IDE", "Agent", "Flow"],
                diagnostics: [
                    "首次安装后建议先在应用内完成初始化。",
                    "桥接配置用于补充，不覆盖应用账号权限。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "桥接 API Key",
                        placeholder: "可选：provider key",
                        helper: "写入 WINDSURF_API_KEY",
                        primaryKey: "WINDSURF_API_KEY"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型偏好",
                        placeholder: "claude-sonnet-4-5",
                        helper: "写入 WINDSURF_MODEL",
                        primaryKey: "WINDSURF_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.workspaceRoot,
                        label: "工作区根目录",
                        placeholder: "/Users/zhangshuo/projects",
                        helper: "写入 WINDSURF_WORKSPACE_ROOT",
                        primaryKey: "WINDSURF_WORKSPACE_ROOT"
                    ),
                ]
            )
        case .trae:
            return genericCLIProfile(
                roleTitle: "TRAE IDE / SOLO",
                roleSubtitle: "官方强调与工作流协作；SOLO 在同一工作区整合编辑器、终端、文档与浏览器。",
                capabilityTags: ["AI IDE", "Context Engineering", "Agent"],
                diagnostics: ["建议在公司网络下同步检查 HTTP/HTTPS 代理。"],
                apiKey: ("TRAE_API_KEY", "TRAE_API_KEY"),
                baseURL: ("TRAE_BASE_URL", "TRAE_BASE_URL"),
                model: ("TRAE_MODEL", "TRAE_MODEL")
            )
        case .kiloCode:
            return genericCLIProfile(
                roleTitle: "Kilo Code",
                roleSubtitle: "官方文档定位为开源 coding agent，用于更快构建、发布与迭代。",
                capabilityTags: ["开源", "Coding Agent", "迭代"],
                diagnostics: ["建议把配置目录纳入备份，避免升级覆盖。"],
                apiKey: ("KILOCODE_API_KEY", "KILOCODE_API_KEY"),
                baseURL: ("KILOCODE_BASE_URL", "KILOCODE_BASE_URL"),
                model: ("KILOCODE_MODEL", "KILOCODE_MODEL")
            )
        case .openclaw:
            return ToolDetailProfile(
                roleTitle: "OpenClaw",
                roleSubtitle: "官方定位“能真正执行任务的 AI”，支持多平台与可扩展工具链。",
                capabilityTags: ["Agent", "多平台", "可扩展"],
                diagnostics: [
                    "同时配置多个 provider 时，建议显式指定主 provider。",
                    "避免多个 key 同时失效造成回退失败。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "主 Provider Key",
                        placeholder: "sk-...",
                        helper: "写入 OPENCLAW_API_KEY",
                        primaryKey: "OPENCLAW_API_KEY",
                        readKeys: ["OPENCLAW_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.provider,
                        label: "主 Provider",
                        placeholder: "openai / anthropic / moonshot",
                        helper: "写入 OPENCLAW_PROVIDER",
                        primaryKey: "OPENCLAW_PROVIDER"
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "主 Provider Base URL",
                        placeholder: "https://api.openai.com/v1",
                        helper: "写入 OPENCLAW_BASE_URL",
                        primaryKey: "OPENCLAW_BASE_URL",
                        readKeys: ["OPENCLAW_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "主模型",
                        placeholder: "gpt-5-codex",
                        helper: "写入 OPENCLAW_MODEL",
                        primaryKey: "OPENCLAW_MODEL"
                    ),
                ]
            )
        case .cline:
            return ToolDetailProfile(
                roleTitle: "Cline",
                roleSubtitle: "官方定位为可在 IDE 内逐步执行复杂开发任务的 agentic coding assistant。",
                capabilityTags: ["IDE Agent", "Human-in-the-loop", "MCP"],
                diagnostics: [
                    "双 provider 混用时，优先保证主路由稳定。",
                    "建议将模型与 provider 一并记录。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "主 Provider Key",
                        placeholder: "sk-...",
                        helper: "写入 CLINE_API_KEY",
                        primaryKey: "CLINE_API_KEY",
                        readKeys: ["CLINE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.provider,
                        label: "主 Provider",
                        placeholder: "openai / anthropic",
                        helper: "写入 CLINE_PROVIDER",
                        primaryKey: "CLINE_PROVIDER"
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "主 Base URL",
                        placeholder: "https://api.openai.com/v1",
                        helper: "写入 CLINE_BASE_URL",
                        primaryKey: "CLINE_BASE_URL",
                        readKeys: ["CLINE_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "写入 CLINE_MODEL",
                        primaryKey: "CLINE_MODEL"
                    ),
                ]
            )
        case .rooCode:
            return ToolDetailProfile(
                roleTitle: "Roo Code",
                roleSubtitle: "官网定位“你的 AI 开发团队”，在编辑器内提供多步骤 agentic coding 协作。",
                capabilityTags: ["AI 开发团队", "IDE Agent", "多步骤"],
                diagnostics: [
                    "复杂任务建议固定主模型并配置回退模型。",
                    "检查 provider 配置与模型归属是否一致。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "主 Provider Key",
                        placeholder: "sk-...",
                        helper: "写入 ROOCODE_API_KEY",
                        primaryKey: "ROOCODE_API_KEY",
                        readKeys: ["ROOCODE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "主 Base URL",
                        placeholder: "https://api.openai.com/v1",
                        helper: "写入 ROOCODE_BASE_URL",
                        primaryKey: "ROOCODE_BASE_URL",
                        readKeys: ["ROOCODE_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "主模型",
                        placeholder: "gpt-5-codex",
                        helper: "写入 ROOCODE_MODEL",
                        primaryKey: "ROOCODE_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.fallbackModel,
                        label: "回退模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "写入 ROOCODE_FALLBACK_MODEL",
                        primaryKey: "ROOCODE_FALLBACK_MODEL"
                    ),
                ]
            )
        case .grokCLI:
            return genericCLIProfile(
                roleTitle: "xAI Grok CLI",
                roleSubtitle: "重点关注 xAI 通道与模型前缀一致性。",
                capabilityTags: ["xAI", "CLI", "单通道"],
                diagnostics: ["建议固定 XAI_BASE_URL，避免环境变量冲突。"],
                apiKey: ("XAI_API_KEY", "XAI_API_KEY"),
                baseURL: ("XAI_BASE_URL", "XAI_BASE_URL"),
                model: ("GROK_MODEL", "GROK_MODEL")
            )
        case .droid:
            return genericCLIProfile(
                roleTitle: "Droid CLI",
                roleSubtitle: "本地执行通道，优先保证配置文件可读可写。",
                capabilityTags: ["CLI", "本地执行", "单通道"],
                diagnostics: ["如使用代理，请先做端口连通性检查。"],
                apiKey: ("DROID_API_KEY", "DROID_API_KEY"),
                baseURL: ("DROID_BASE_URL", "DROID_BASE_URL"),
                model: ("DROID_MODEL", "DROID_MODEL")
            )
        case .zed:
            return ToolDetailProfile(
                roleTitle: "Zed 编辑器桥接",
                roleSubtitle: "以编辑器内 provider 配置为主，CLI 配置用于兼容桥接。",
                capabilityTags: ["Desktop IDE", "Provider", "桥接配置"],
                diagnostics: [
                    "优先检查 Zed 应用内 provider 设置。",
                    "桥接模型用于 CLI 场景，不强制覆盖编辑器设置。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "桥接 API Key",
                        placeholder: "sk-...",
                        helper: "写入 ZED_API_KEY",
                        primaryKey: "ZED_API_KEY"
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型偏好",
                        placeholder: "gpt-5-codex",
                        helper: "写入 ZED_MODEL",
                        primaryKey: "ZED_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.workspaceRoot,
                        label: "工作区根目录",
                        placeholder: "/Users/zhangshuo/Workspace",
                        helper: "写入 ZED_WORKSPACE_ROOT",
                        primaryKey: "ZED_WORKSPACE_ROOT"
                    ),
                ]
            )
        case .monkeyCode:
            return genericCLIProfile(
                roleTitle: "MonkeyCode CLI",
                roleSubtitle: "面向本地代码执行，建议保持 key / endpoint / model 三项一致。",
                capabilityTags: ["CLI", "本地执行", "单通道"],
                diagnostics: ["建议在更新后复检配置文件字段完整性。"],
                apiKey: ("MONKEYCODE_API_KEY", "MONKEYCODE_API_KEY"),
                baseURL: ("MONKEYCODE_BASE_URL", "MONKEYCODE_BASE_URL"),
                model: ("MONKEYCODE_MODEL", "MONKEYCODE_MODEL")
            )
        case .githubCopilotCLI:
            return ToolDetailProfile(
                roleTitle: "GitHub Copilot CLI",
                roleSubtitle: "GitHub 官方开源命令行助手，可把自然语言转为 shell / git 操作并接入 Copilot 能力。",
                capabilityTags: ["GitHub", "CLI 助手", "Shell/Git"],
                diagnostics: [
                    "优先检查 ~/.copilot/lsp-config.json 是否存在且可读。",
                    "若 copilot 命令不可用，请检查 npm / brew 安装路径是否在 PATH。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "GitHub Token",
                        placeholder: "ghp_...",
                        helper: "读取 GITHUB_TOKEN / GH_TOKEN",
                        primaryKey: "GITHUB_TOKEN",
                        readKeys: ["GITHUB_TOKEN", "GH_TOKEN", "github_token", "token"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "Copilot 模型偏好",
                        placeholder: "gpt-4o-mini",
                        helper: "读取 COPILOT_MODEL",
                        primaryKey: "COPILOT_MODEL"
                    ),
                    textField(
                        id: ToolEditableFieldID.workspaceRoot,
                        label: "工作区根目录",
                        placeholder: "/Users/zhangshuo/workspace",
                        helper: "读取 COPILOT_WORKSPACE_ROOT",
                        primaryKey: "COPILOT_WORKSPACE_ROOT"
                    ),
                ]
            )
        case .aider:
            return ToolDetailProfile(
                roleTitle: "Aider CLI",
                roleSubtitle: "开源终端 pair-programming agent，擅长基于 git diff 的多文件改动与审阅。",
                capabilityTags: ["开源", "终端 Agent", "Git 工作流"],
                diagnostics: [
                    "优先检查 ~/.aider.conf.yml 是否已写入默认模型。",
                    "若 provider 混用，确认 OPENAI_BASE_URL 与模型前缀一致。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "主 Provider Key",
                        placeholder: "sk-...",
                        helper: "读取 OPENAI_API_KEY / ANTHROPIC_API_KEY",
                        primaryKey: "OPENAI_API_KEY",
                        readKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "Provider Base URL",
                        placeholder: "https://api.openai.com/v1",
                        helper: "读取 OPENAI_BASE_URL",
                        primaryKey: "OPENAI_BASE_URL",
                        readKeys: ["OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "gpt-4o",
                        helper: "读取 AIDER_MODEL",
                        primaryKey: "AIDER_MODEL",
                        readKeys: ["AIDER_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .goose:
            return ToolDetailProfile(
                roleTitle: "Goose CLI",
                roleSubtitle: "Block 官方的本地 AI agent，强调结构化会话、扩展与可控执行。",
                capabilityTags: ["Block", "本地 Agent", "扩展化"],
                diagnostics: [
                    "优先检查 ~/.config/goose/config.yaml 与 secrets.yaml 是否同时存在。",
                    "若 provider 切换失败，先确认 secrets 文件中的凭据键名。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Provider Key",
                        placeholder: "sk-...",
                        helper: "读取 GOOSE_API_KEY",
                        primaryKey: "GOOSE_API_KEY",
                        readKeys: ["GOOSE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.provider,
                        label: "主 Provider",
                        placeholder: "openai / anthropic",
                        helper: "读取 GOOSE_PROVIDER",
                        primaryKey: "GOOSE_PROVIDER",
                        readKeys: ["GOOSE_PROVIDER", "provider"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "读取 GOOSE_MODEL",
                        primaryKey: "GOOSE_MODEL",
                        readKeys: ["GOOSE_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .plandex:
            return ToolDetailProfile(
                roleTitle: "Plandex CLI",
                roleSubtitle: "面向大型编码任务的 plan-first CLI agent，支持上下文分层与批量改动。",
                capabilityTags: ["Plan-first", "大型任务", "CLI Agent"],
                diagnostics: [
                    "建议先确认 OPENROUTER_API_KEY 是否可用，再检查计划执行链路。",
                    "若本地配置路径为空，请以官方安装脚本与文档为准。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "路由 API Key",
                        placeholder: "sk-or-...",
                        helper: "读取 OPENROUTER_API_KEY",
                        primaryKey: "OPENROUTER_API_KEY",
                        readKeys: ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "路由 Base URL",
                        placeholder: "https://openrouter.ai/api/v1",
                        helper: "读取 OPENROUTER_BASE_URL",
                        primaryKey: "OPENROUTER_BASE_URL",
                        readKeys: ["OPENROUTER_BASE_URL", "OPENAI_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "计划模型",
                        placeholder: "openai/gpt-5",
                        helper: "读取 PLANDEX_MODEL",
                        primaryKey: "PLANDEX_MODEL",
                        readKeys: ["PLANDEX_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .openHands:
            return ToolDetailProfile(
                roleTitle: "OpenHands CLI",
                roleSubtitle: "OpenHands 官方 CLI，可在本地/远端执行 agent 任务并保持会话上下文。",
                capabilityTags: ["OpenHands", "任务执行", "会话上下文"],
                diagnostics: [
                    "优先检查 ~/.openhands/settings.json 与 conversations 目录权限。",
                    "使用 uv 安装时，确认 uv tool 的 bin 目录已加入 PATH。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "OpenHands API Key",
                        placeholder: "sk-...",
                        helper: "读取 OPENHANDS_API_KEY",
                        primaryKey: "OPENHANDS_API_KEY",
                        readKeys: ["OPENHANDS_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "服务地址",
                        placeholder: "https://api.openai.com/v1",
                        helper: "读取 OPENHANDS_BASE_URL",
                        primaryKey: "OPENHANDS_BASE_URL",
                        readKeys: ["OPENHANDS_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "读取 OPENHANDS_MODEL",
                        primaryKey: "OPENHANDS_MODEL",
                        readKeys: ["OPENHANDS_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .continueCLI:
            return ToolDetailProfile(
                roleTitle: "Continue CLI",
                roleSubtitle: "Continue 官方命令行入口，聚焦模型网关、权限策略与团队规范执行。",
                capabilityTags: ["Continue", "CLI", "团队规范"],
                diagnostics: [
                    "优先检查 ~/.continue/config.yaml 与 permissions.yaml 是否一致。",
                    "若命令执行异常，查看 ~/.continue/logs/cn.log。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Provider API Key",
                        placeholder: "sk-...",
                        helper: "读取 CONTINUE_API_KEY",
                        primaryKey: "CONTINUE_API_KEY",
                        readKeys: ["CONTINUE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.provider,
                        label: "主 Provider",
                        placeholder: "openai / anthropic",
                        helper: "读取 CONTINUE_PROVIDER",
                        primaryKey: "CONTINUE_PROVIDER",
                        readKeys: ["CONTINUE_PROVIDER", "provider"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "gpt-5",
                        helper: "读取 CONTINUE_MODEL",
                        primaryKey: "CONTINUE_MODEL",
                        readKeys: ["CONTINUE_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .amp:
            return ToolDetailProfile(
                roleTitle: "Amp CLI",
                roleSubtitle: "Amp 命令行工作流，强调对代码库执行与结构化代理指令（AGENTS.md）。",
                capabilityTags: ["Sourcegraph", "CLI Agent", "AGENTS.md"],
                diagnostics: [
                    "优先检查 ~/.config/amp/AGENTS.md 是否可读。",
                    "若 npm 全局安装失败，先修复 npm 缓存权限再重试。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Amp Token",
                        placeholder: "sgp_...",
                        helper: "读取 AMP_API_KEY / SOURCEGRAPH_ACCESS_TOKEN",
                        primaryKey: "AMP_API_KEY",
                        readKeys: ["AMP_API_KEY", "SOURCEGRAPH_ACCESS_TOKEN", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "服务地址",
                        placeholder: "https://sourcegraph.com",
                        helper: "读取 AMP_BASE_URL",
                        primaryKey: "AMP_BASE_URL",
                        readKeys: ["AMP_BASE_URL", "SRC_ENDPOINT", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "读取 AMP_MODEL",
                        primaryKey: "AMP_MODEL",
                        readKeys: ["AMP_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .kiro:
            return ToolDetailProfile(
                roleTitle: "Kiro CLI",
                roleSubtitle: "Kiro 官方 CLI，主打会话式编码与快速任务执行。",
                capabilityTags: ["Kiro", "CLI", "会话式编码"],
                diagnostics: [
                    "Kiro 常以账号登录为主，环境变量可能并非唯一配置来源。",
                    "若路径与字段未检出，请以官方 CLI 文档为准。"
                ],
                editableFields: [
                    textField(
                        id: ToolEditableFieldID.provider,
                        label: "Provider 偏好",
                        placeholder: "kiro-managed",
                        helper: "读取 KIRO_PROVIDER",
                        primaryKey: "KIRO_PROVIDER",
                        readKeys: ["KIRO_PROVIDER", "provider"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "kiro-default",
                        helper: "读取 KIRO_MODEL",
                        primaryKey: "KIRO_MODEL",
                        readKeys: ["KIRO_MODEL", "model", "default_model"]
                    ),
                    textField(
                        id: ToolEditableFieldID.workspaceRoot,
                        label: "工作区根目录",
                        placeholder: "/Users/zhangshuo/workspace",
                        helper: "读取 KIRO_WORKSPACE_ROOT",
                        primaryKey: "KIRO_WORKSPACE_ROOT"
                    ),
                ]
            )
        case .cody:
            return ToolDetailProfile(
                roleTitle: "Cody CLI",
                roleSubtitle: "Sourcegraph Cody CLI，支持聊天、命令执行与仓库上下文问答。",
                capabilityTags: ["Sourcegraph", "CLI", "代码上下文"],
                diagnostics: [
                    "优先检查 Sourcegraph endpoint 与 token 是否匹配实例权限。",
                    "企业私有部署时需确认 SRC_ENDPOINT 可达。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "Sourcegraph Token",
                        placeholder: "sgp_...",
                        helper: "读取 SRC_ACCESS_TOKEN",
                        primaryKey: "SRC_ACCESS_TOKEN",
                        readKeys: ["SRC_ACCESS_TOKEN", "CODY_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "Sourcegraph Endpoint",
                        placeholder: "https://sourcegraph.com",
                        helper: "读取 SRC_ENDPOINT",
                        primaryKey: "SRC_ENDPOINT",
                        readKeys: ["SRC_ENDPOINT", "CODY_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "claude-sonnet-4-5",
                        helper: "读取 CODY_MODEL",
                        primaryKey: "CODY_MODEL",
                        readKeys: ["CODY_MODEL", "model", "default_model"]
                    ),
                ]
            )
        case .qwenCode:
            return ToolDetailProfile(
                roleTitle: "Qwen Code",
                roleSubtitle: "Qwen 官方 CLI 代码助手，支持 OpenAI/Anthropic/Gemini 兼容协议与多模型切换。",
                capabilityTags: ["Qwen", "多协议", "CLI Agent"],
                diagnostics: [
                    "优先检查 ~/.qwen/settings.json 是否存在且 JSON 结构完整。",
                    "若使用 OpenAI 兼容网关，确认 base_url 与模型供应商一致。"
                ],
                editableFields: [
                    secureField(
                        id: ToolEditableFieldID.apiKey,
                        label: "主 API Key",
                        placeholder: "sk-...",
                        helper: "读取 OPENAI_API_KEY / ANTHROPIC_API_KEY / GEMINI_API_KEY",
                        primaryKey: "OPENAI_API_KEY",
                        readKeys: ["OPENAI_API_KEY", "QWEN_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "api_key"]
                    ),
                    textField(
                        id: ToolEditableFieldID.baseURL,
                        label: "网关地址",
                        placeholder: "https://api.openai.com/v1",
                        helper: "读取 OPENAI_BASE_URL",
                        primaryKey: "OPENAI_BASE_URL",
                        readKeys: ["OPENAI_BASE_URL", "QWEN_BASE_URL", "base_url"]
                    ),
                    textField(
                        id: ToolEditableFieldID.model,
                        label: "默认模型",
                        placeholder: "qwen-plus-latest",
                        helper: "读取 QWEN_MODEL",
                        primaryKey: "QWEN_MODEL",
                        readKeys: ["QWEN_MODEL", "model", "default_model"]
                    ),
                ]
            )
        }
    }

    private static func genericCLIProfile(
        roleTitle: String,
        roleSubtitle: String,
        capabilityTags: [String],
        diagnostics: [String],
        apiKey: (String, String),
        baseURL: (String, String),
        model: (String, String)
    ) -> ToolDetailProfile {
        ToolDetailProfile(
            roleTitle: roleTitle,
            roleSubtitle: roleSubtitle,
            capabilityTags: capabilityTags,
            diagnostics: diagnostics,
            editableFields: [
                secureField(
                    id: ToolEditableFieldID.apiKey,
                    label: "API Key",
                    placeholder: "sk-...",
                    helper: "写入 \(apiKey.0)",
                    primaryKey: apiKey.0,
                    canonicalKey: apiKey.1
                ),
                textField(
                    id: ToolEditableFieldID.baseURL,
                    label: "Base URL",
                    placeholder: "https://api.example.com/v1",
                    helper: "写入 \(baseURL.0)",
                    primaryKey: baseURL.0,
                    canonicalKey: baseURL.1
                ),
                textField(
                    id: ToolEditableFieldID.model,
                    label: "默认模型",
                    placeholder: "gpt-5-codex",
                    helper: "写入 \(model.0)",
                    primaryKey: model.0,
                    canonicalKey: model.1
                ),
            ]
        )
    }

    private static func secureField(
        id: String,
        label: String,
        placeholder: String,
        helper: String,
        primaryKey: String,
        canonicalKey: String? = nil,
        readKeys: [String]? = nil
    ) -> ToolEditableFieldDescriptor {
        ToolEditableFieldDescriptor(
            id: id,
            label: label,
            placeholder: placeholder,
            helper: helper,
            isSecure: true,
            primaryKey: primaryKey,
            canonicalKey: canonicalKey ?? id,
            readKeys: readKeys ?? [primaryKey, canonicalKey ?? id]
        )
    }

    private static func textField(
        id: String,
        label: String,
        placeholder: String,
        helper: String,
        primaryKey: String,
        canonicalKey: String? = nil,
        readKeys: [String]? = nil
    ) -> ToolEditableFieldDescriptor {
        ToolEditableFieldDescriptor(
            id: id,
            label: label,
            placeholder: placeholder,
            helper: helper,
            isSecure: false,
            primaryKey: primaryKey,
            canonicalKey: canonicalKey ?? id,
            readKeys: readKeys ?? [primaryKey, canonicalKey ?? id]
        )
    }
}

extension ProgrammingTool {
    var supportedEditableFieldIDs: Set<String> {
        switch self {
        case .codex, .claudeCode:
            return [
                ToolEditableFieldID.apiKey,
                ToolEditableFieldID.baseURL,
                ToolEditableFieldID.model,
            ]
        default:
            return []
        }
    }

    var supportedEditableFields: [ToolEditableFieldDescriptor] {
        let allowedIDs = supportedEditableFieldIDs
        guard !allowedIDs.isEmpty else { return [] }
        return detailProfile.editableFields.filter { descriptor in
            allowedIDs.contains(descriptor.id)
        }
    }

    var detailProfile: ToolDetailProfile {
        ToolDetailProfileFactory.profile(for: self)
    }
}
