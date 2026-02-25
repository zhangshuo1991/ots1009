import Foundation

enum ConfigurationValueState: String {
    case configured
    case warning
    case missing
    case informational
}

struct ConfigurationVisualItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let state: ConfigurationValueState
}

struct ConfigurationVisualSection: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let items: [ConfigurationVisualItem]
}

struct ToolConfigurationVisualization {
    let title: String
    let summary: String
    let sections: [ConfigurationVisualSection]
    let notes: [String]
}

enum ToolConfigurationVisualizationBuilder {
    static func build(
        tool: ProgrammingTool,
        configService: ConfigEditorService,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configPathCandidates: [String]? = nil
    ) -> ToolConfigurationVisualization {
        let profile = profile(for: tool)
        let candidatePaths = configPathCandidates ?? tool.configPaths
        let existingPath = candidatePaths.first { path in
            fileManager.fileExists(atPath: (path as NSString).expandingTildeInPath)
        }
        let loadedConfig = existingPath.flatMap { path -> ToolConfig? in
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return nil
            }
            return configService.loadConfigSync(from: path)
        }
        let fileValues = extractFileValues(
            from: candidatePaths,
            existingPath: existingPath,
            fileManager: fileManager
        )

        let keySectionItems: [ConfigurationVisualItem]
        if tool.supportsDirectConfigEditing {
            let credentialValue = firstNonEmptyValue(
                keys: profile.credentialKeys,
                environment: environment,
                fileValues: fileValues,
                configValue: loadedConfig?.apiKey
            )
            let modelValue = firstNonEmptyValue(
                keys: profile.modelKeys,
                environment: environment,
                fileValues: fileValues,
                configValue: loadedConfig?.model
            )
            let httpProxyValue = firstNonEmptyValue(
                keys: ["HTTP_PROXY", "http_proxy"],
                environment: environment,
                fileValues: fileValues,
                configValue: loadedConfig?.httpProxy
            )
            let httpsProxyValue = firstNonEmptyValue(
                keys: ["HTTPS_PROXY", "https_proxy"],
                environment: environment,
                fileValues: fileValues,
                configValue: loadedConfig?.httpsProxy
            )
            let endpointValue = firstNonEmptyValue(
                keys: profile.endpointKeys,
                environment: environment,
                fileValues: fileValues,
                configValue: nil
            )

            keySectionItems = [
                ConfigurationVisualItem(
                    id: "credential",
                    title: "认证凭据",
                    value: maskedSecret(credentialValue),
                    detail: profile.credentialKeys.joined(separator: " / "),
                    state: credentialValue == nil ? .warning : .configured
                ),
                ConfigurationVisualItem(
                    id: "model",
                    title: "默认模型",
                    value: modelValue ?? "未配置",
                    detail: profile.modelKeys.joined(separator: " / "),
                    state: modelValue == nil ? .warning : .configured
                ),
                ConfigurationVisualItem(
                    id: "endpoint",
                    title: "服务地址",
                    value: endpointValue ?? "默认",
                    detail: profile.endpointKeys.isEmpty ? "无专用地址变量" : profile.endpointKeys.joined(separator: " / "),
                    state: endpointValue == nil ? .informational : .configured
                ),
                ConfigurationVisualItem(
                    id: "proxy",
                    title: "网络代理",
                    value: resolvedProxyLabel(httpProxy: httpProxyValue, httpsProxy: httpsProxyValue),
                    detail: "HTTP_PROXY / HTTPS_PROXY",
                    state: (httpProxyValue == nil && httpsProxyValue == nil) ? .informational : .configured
                ),
            ]
        } else {
            keySectionItems = [
                ConfigurationVisualItem(
                    id: "managed-mode",
                    title: "配置方式",
                    value: "官方客户端管理",
                    detail: "该工具不支持在本应用内直接编辑 API Key / Base URL / 模型",
                    state: .informational
                ),
                ConfigurationVisualItem(
                    id: "managed-path",
                    title: "本地配置状态",
                    value: existingPath ?? "未检测到可读配置文件",
                    detail: existingPath == nil ? "请先在官方客户端完成初始化" : "已发现配置文件，可用于只读诊断",
                    state: existingPath == nil ? .informational : .configured
                ),
            ]
        }

        let keySection = ConfigurationVisualSection(
            id: "key-\(tool.rawValue)",
            title: profile.coreSectionTitle,
            subtitle: profile.coreSectionSubtitle,
            items: keySectionItems
        )

        let pathItems = tool.configPaths.map { path -> ConfigurationVisualItem in
            let expanded = (path as NSString).expandingTildeInPath
            let exists = fileManager.fileExists(atPath: expanded)
            return ConfigurationVisualItem(
                id: path,
                title: exists ? "配置已落盘" : "候选路径",
                value: path,
                detail: exists ? "文件存在，可直接读取" : "建议先打开设置完成初始化",
                state: exists ? .configured : .missing
            )
        }

        let existingCount = pathItems.filter { $0.state == .configured }.count
        let pathSection = ConfigurationVisualSection(
            id: "path-\(tool.rawValue)",
            title: "配置文件覆盖",
            subtitle: "已检测到 \(existingCount)/\(pathItems.count) 条配置路径",
            items: pathItems
        )

        let notes = profile.notes + [
            existingPath == nil ? "当前未找到可读取配置文件，可先点击“打开设置”写入。"
                                : "已读取配置文件：\(existingPath ?? "")"
        ]

        return ToolConfigurationVisualization(
            title: profile.visualTitle,
            summary: profile.summary,
            sections: [keySection, pathSection],
            notes: notes
        )
    }

    private static func firstNonEmptyValue(
        keys: [String],
        environment: [String: String],
        fileValues: [String: String],
        configValue: String?
    ) -> String? {
        for key in keys {
            let normalized = normalizedLookupKey(key)
            if let value = fileValues[normalized]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        if let configValue {
            let trimmed = configValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private static func extractFileValues(
        from candidatePaths: [String],
        existingPath: String?,
        fileManager: FileManager
    ) -> [String: String] {
        var merged: [String: String] = [:]
        var scanTargets: [String] = []

        if let existingPath {
            scanTargets.append(existingPath)
        }
        for path in candidatePaths where !scanTargets.contains(path) {
            scanTargets.append(path)
        }

        for rawPath in scanTargets {
            let expanded = (rawPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expanded, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                let files = candidateConfigFiles(in: expanded, fileManager: fileManager)
                for file in files {
                    merge(fileValues: parseFile(at: file, fileManager: fileManager), into: &merged)
                }
            } else {
                merge(fileValues: parseFile(at: expanded, fileManager: fileManager), into: &merged)
            }
        }

        return merged
    }

    private static func candidateConfigFiles(in directory: String, fileManager: FileManager) -> [String] {
        let candidates = [
            "config.toml",
            "settings.toml",
            "config.json",
            "settings.json",
            "auth.json",
            ".env",
            "credentials.json"
        ]

        var files: [String] = []
        for filename in candidates {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(filename).path
            if fileManager.fileExists(atPath: path) {
                files.append(path)
            }
        }
        return files
    }

    private static func parseFile(at path: String, fileManager: FileManager) -> [String: String] {
        guard let data = fileManager.contents(atPath: path) else { return [:] }
        let lowerPath = path.lowercased()

        if lowerPath.hasSuffix(".json") {
            return parseJSONFile(data)
        }
        if lowerPath.hasSuffix(".toml") {
            return parseTOMLFile(data)
        }
        if lowerPath.hasSuffix(".env") {
            return parseEnvFile(data)
        }

        return [:]
    }

    private static func parseJSONFile(_ data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var result: [String: String] = [:]
        flattenJSONObject(object, prefix: nil, into: &result)
        return result
    }

    private static func flattenJSONObject(_ object: Any, prefix: String?, into result: inout [String: String]) {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                let current = prefix == nil ? key : "\(prefix!).\(key)"
                flattenJSONObject(value, prefix: current, into: &result)
            }
            return
        }

        if let array = object as? [Any] {
            let joined = array.compactMap { value -> String? in
                if let str = value as? String { return str }
                if let num = value as? NSNumber { return num.stringValue }
                return nil
            }.joined(separator: ", ")
            if let prefix, !joined.isEmpty {
                insertValue(joined, for: prefix, into: &result)
            }
            return
        }

        let value: String
        switch object {
        case let string as String:
            value = string
        case let number as NSNumber:
            value = number.stringValue
        case let bool as Bool:
            value = bool ? "true" : "false"
        default:
            return
        }

        if let prefix {
            insertValue(value, for: prefix, into: &result)
        }
    }

    private static func parseTOMLFile(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        var sectionPath: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                sectionPath = section.split(separator: ".").map { component in
                    component.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
                continue
            }

            guard let equalIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = line[line.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let commentIndex = value.firstIndex(of: "#") {
                value = value[..<commentIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let unwrapped = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let fullKey = (sectionPath + [key]).joined(separator: ".")
            insertValue(unwrapped, for: fullKey, into: &result)
        }

        return result
    }

    private static func parseEnvFile(_ data: Data) -> [String: String] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let equalIndex = line.firstIndex(of: "=") else { continue }
            let key = line[..<equalIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: equalIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            insertValue(value.trimmingCharacters(in: CharacterSet(charactersIn: "\"")), for: key, into: &result)
        }

        return result
    }

    private static func merge(fileValues: [String: String], into target: inout [String: String]) {
        for (key, value) in fileValues {
            target[key] = value
        }
    }

    private static func insertValue(_ value: String, for key: String, into result: inout [String: String]) {
        let normalizedKey = normalizedLookupKey(key)
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result[normalizedKey] = value
        }

        if let leaf = normalizedKey.split(separator: ".").last {
            let leafKey = String(leaf)
            if result[leafKey] == nil {
                result[leafKey] = value
            }
        }
    }

    private static func normalizedLookupKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "__", with: "_")
            .lowercased()
    }

    private static func maskedSecret(_ value: String?) -> String {
        guard let value else { return "未配置" }
        if value.count <= 8 {
            return "已配置"
        }
        let prefix = value.prefix(4)
        let suffix = value.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private static func resolvedProxyLabel(httpProxy: String?, httpsProxy: String?) -> String {
        switch (httpProxy, httpsProxy) {
        case let (http?, https?) where !http.isEmpty && !https.isEmpty:
            return "HTTP + HTTPS"
        case let (http?, _) where !http.isEmpty:
            return "仅 HTTP"
        case let (_, https?) where !https.isEmpty:
            return "仅 HTTPS"
        default:
            return "未配置"
        }
    }

    private struct ToolProfile {
        let visualTitle: String
        let summary: String
        let coreSectionTitle: String
        let coreSectionSubtitle: String
        let credentialKeys: [String]
        let endpointKeys: [String]
        let modelKeys: [String]
        let notes: [String]
    }

    private static func profile(for tool: ProgrammingTool) -> ToolProfile {
        switch tool {
        case .codex:
            return ToolProfile(
                visualTitle: "Codex 配置总览",
                summary: "重点关注 OpenAI 凭据、模型与代理。",
                coreSectionTitle: "推理配置",
                coreSectionSubtitle: "以 OpenAI 通道为主",
                credentialKeys: ["OPENAI_API_KEY", "api_key"],
                endpointKeys: ["OPENAI_BASE_URL", "model_providers.codex.base_url", "base_url"],
                modelKeys: ["OPENAI_MODEL", "CODEX_MODEL", "model"],
                notes: ["建议同时校验 OPENAI_BASE_URL 与模型名是否匹配账号权限。"]
            )
        case .claudeCode:
            return ToolProfile(
                visualTitle: "Claude Code 配置总览",
                summary: "重点关注 Anthropic 凭据、模型与代理。",
                coreSectionTitle: "Anthropic 配置",
                coreSectionSubtitle: "以 Claude API 为主",
                credentialKeys: ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "api_key"],
                endpointKeys: ["ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["ANTHROPIC_MODEL", "CLAUDE_MODEL", "model", "default_model"],
                notes: ["优先确认 API Key 与默认模型是否同时配置。"]
            )
        case .kimiCLI:
            return ToolProfile(
                visualTitle: "Kimi CLI 配置总览",
                summary: "重点关注 Moonshot/Kimi 凭据与模型。",
                coreSectionTitle: "Moonshot 配置",
                coreSectionSubtitle: "Kimi 兼容 OpenAI 协议",
                credentialKeys: ["MOONSHOT_API_KEY", "KIMI_API_KEY", "OPENAI_API_KEY", "api_key"],
                endpointKeys: ["MOONSHOT_BASE_URL", "OPENAI_BASE_URL", "base_url"],
                modelKeys: ["KIMI_MODEL", "MOONSHOT_MODEL", "model", "default_model"],
                notes: ["若走 OpenAI 兼容地址，请确保 Base URL 与模型前缀一致。"]
            )
        case .opencode:
            return ToolProfile(
                visualTitle: "OpenCode 配置总览",
                summary: "重点关注路由凭据与模型切换。",
                coreSectionTitle: "路由配置",
                coreSectionSubtitle: "常见接入 OpenRouter 或 OpenAI",
                credentialKeys: ["OPENCODE_API_KEY", "OPENROUTER_API_KEY", "OPENAI_API_KEY", "api_key"],
                endpointKeys: ["OPENROUTER_BASE_URL", "OPENAI_BASE_URL", "base_url"],
                modelKeys: ["OPENCODE_MODEL", "OPENROUTER_MODEL", "model", "default_model"],
                notes: ["多路由场景建议固定默认模型，避免请求漂移。"]
            )
        case .geminiCLI:
            return ToolProfile(
                visualTitle: "Gemini CLI 配置总览",
                summary: "重点关注 Google 凭据与模型。",
                coreSectionTitle: "Google 配置",
                coreSectionSubtitle: "Gemini API / Vertex AI",
                credentialKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "api_key"],
                endpointKeys: ["GOOGLE_CLOUD_PROJECT", "GOOGLE_CLOUD_LOCATION"],
                modelKeys: ["GEMINI_MODEL", "model", "default_model"],
                notes: ["使用 Vertex AI 时应同时配置 project 与 location。"]
            )
        case .cursor:
            return ToolProfile(
                visualTitle: "Cursor 配置总览",
                summary: "重点关注本地配置与扩展目录健康度。",
                coreSectionTitle: "编辑器集成",
                coreSectionSubtitle: "本地用户配置优先",
                credentialKeys: ["CURSOR_API_KEY"],
                endpointKeys: [],
                modelKeys: ["CURSOR_MODEL", "model", "default_model"],
                notes: ["建议定期检查 User 配置目录是否可写。"]
            )
        case .windsurf:
            return ToolProfile(
                visualTitle: "Windsurf 配置总览",
                summary: "重点关注用户配置目录与默认模型。",
                coreSectionTitle: "编辑器集成",
                coreSectionSubtitle: "本地配置驱动",
                credentialKeys: ["WINDSURF_API_KEY"],
                endpointKeys: [],
                modelKeys: ["WINDSURF_MODEL", "model", "default_model"],
                notes: ["首次安装后通常需完成一次应用内初始化。"]
            )
        case .trae:
            return ToolProfile(
                visualTitle: "Trae 配置总览",
                summary: "重点关注认证与代理可达性。",
                coreSectionTitle: "运行配置",
                coreSectionSubtitle: "CLI 直连模式",
                credentialKeys: ["TRAE_API_KEY"],
                endpointKeys: ["TRAE_BASE_URL", "base_url"],
                modelKeys: ["TRAE_MODEL", "model", "default_model"],
                notes: ["若处于公司网络，优先校验代理配置。"]
            )
        case .kiloCode:
            return ToolProfile(
                visualTitle: "KiloCode 配置总览",
                summary: "重点关注 API 凭据和配置路径落盘。",
                coreSectionTitle: "运行配置",
                coreSectionSubtitle: "本地配置文件模式",
                credentialKeys: ["KILOCODE_API_KEY"],
                endpointKeys: ["KILOCODE_BASE_URL", "base_url"],
                modelKeys: ["KILOCODE_MODEL", "model", "default_model"],
                notes: ["建议把关键配置纳入版本化备份。"]
            )
        case .openclaw:
            return ToolProfile(
                visualTitle: "OpenClaw 配置总览",
                summary: "重点关注 provider key 与 endpoint。",
                coreSectionTitle: "Provider 配置",
                coreSectionSubtitle: "多供应商接入",
                credentialKeys: ["OPENCLAW_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: ["OPENCLAW_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["OPENCLAW_MODEL", "model", "default_model"],
                notes: ["多 provider 并存时建议显式指定模型来源。"]
            )
        case .cline:
            return ToolProfile(
                visualTitle: "Cline 配置总览",
                summary: "重点关注 provider 凭据与代理。",
                coreSectionTitle: "Provider 配置",
                coreSectionSubtitle: "常见 OpenAI/Anthropic 双路",
                credentialKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: ["OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["CLINE_MODEL", "model", "default_model"],
                notes: ["建议避免多个 API Key 同时过期导致回退失败。"]
            )
        case .rooCode:
            return ToolProfile(
                visualTitle: "RooCode 配置总览",
                summary: "重点关注 API 凭据与模型固定策略。",
                coreSectionTitle: "Provider 配置",
                coreSectionSubtitle: "多模型执行链路",
                credentialKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ROOCODE_API_KEY", "api_key"],
                endpointKeys: ["OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["ROOCODE_MODEL", "model", "default_model"],
                notes: ["对复杂任务建议固定主模型并记录回退模型。"]
            )
        case .grokCLI:
            return ToolProfile(
                visualTitle: "Grok CLI 配置总览",
                summary: "重点关注 xAI 凭据与 endpoint。",
                coreSectionTitle: "xAI 配置",
                coreSectionSubtitle: "Grok API 通道",
                credentialKeys: ["XAI_API_KEY", "GROK_API_KEY", "api_key"],
                endpointKeys: ["XAI_BASE_URL", "GROK_BASE_URL", "base_url"],
                modelKeys: ["GROK_MODEL", "model", "default_model"],
                notes: ["建议固定 endpoint，避免环境变量被其它工具覆盖。"]
            )
        case .droid:
            return ToolProfile(
                visualTitle: "Droid 配置总览",
                summary: "重点关注认证与代理可用性。",
                coreSectionTitle: "运行配置",
                coreSectionSubtitle: "CLI 执行上下文",
                credentialKeys: ["DROID_API_KEY"],
                endpointKeys: ["DROID_BASE_URL", "base_url"],
                modelKeys: ["DROID_MODEL", "model", "default_model"],
                notes: ["建议对代理异常做单独连通性验证。"]
            )
        case .zed:
            return ToolProfile(
                visualTitle: "Zed 配置总览",
                summary: "重点关注编辑器配置目录和 provider key。",
                coreSectionTitle: "编辑器集成",
                coreSectionSubtitle: "本地配置 + provider",
                credentialKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: [],
                modelKeys: ["ZED_MODEL", "model", "default_model"],
                notes: ["Zed 常通过编辑器内 provider 配置驱动。"]
            )
        case .monkeyCode:
            return ToolProfile(
                visualTitle: "MonkeyCode 配置总览",
                summary: "重点关注 API 凭据与模型映射。",
                coreSectionTitle: "运行配置",
                coreSectionSubtitle: "本地配置文件模式",
                credentialKeys: ["MONKEYCODE_API_KEY"],
                endpointKeys: ["MONKEYCODE_BASE_URL", "base_url"],
                modelKeys: ["MONKEYCODE_MODEL", "model", "default_model"],
                notes: ["建议优先保证 key、model、endpoint 三项一致。"]
            )
        case .githubCopilotCLI:
            return ToolProfile(
                visualTitle: "GitHub Copilot CLI 配置总览",
                summary: "重点关注 GitHub 认证态与 CLI 工作区配置。",
                coreSectionTitle: "GitHub 配置",
                coreSectionSubtitle: "Copilot CLI + 本地配置",
                credentialKeys: ["GITHUB_TOKEN", "GH_TOKEN", "token"],
                endpointKeys: ["GITHUB_API_URL", "base_url"],
                modelKeys: ["COPILOT_MODEL", "model", "default_model"],
                notes: ["建议先确认 ~/.copilot/lsp-config.json 已落盘，再排查命令可用性。"]
            )
        case .aider:
            return ToolProfile(
                visualTitle: "Aider 配置总览",
                summary: "重点关注 provider key、base URL 与默认模型。",
                coreSectionTitle: "Provider 配置",
                coreSectionSubtitle: "OpenAI / Anthropic / Gemini",
                credentialKeys: ["OPENAI_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "api_key"],
                endpointKeys: ["OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["AIDER_MODEL", "model", "default_model"],
                notes: ["建议固定默认模型，避免多 provider 自动回退导致行为漂移。"]
            )
        case .goose:
            return ToolProfile(
                visualTitle: "Goose 配置总览",
                summary: "重点关注 config/secrets 双文件一致性。",
                coreSectionTitle: "Goose 运行配置",
                coreSectionSubtitle: "config.yaml + secrets.yaml",
                credentialKeys: ["GOOSE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: ["GOOSE_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["GOOSE_MODEL", "model", "default_model"],
                notes: ["建议同时检查 ~/.config/goose/config.yaml 与 secrets.yaml。"]
            )
        case .plandex:
            return ToolProfile(
                visualTitle: "Plandex 配置总览",
                summary: "重点关注路由凭据、执行模型与计划上下文目录。",
                coreSectionTitle: "计划执行配置",
                coreSectionSubtitle: "Plan-first CLI 工作流",
                credentialKeys: ["OPENROUTER_API_KEY", "OPENAI_API_KEY", "api_key"],
                endpointKeys: ["OPENROUTER_BASE_URL", "OPENAI_BASE_URL", "base_url"],
                modelKeys: ["PLANDEX_MODEL", "model", "default_model"],
                notes: ["若路径未检测到，请以官方安装脚本和文档路径为准。"]
            )
        case .openHands:
            return ToolProfile(
                visualTitle: "OpenHands CLI 配置总览",
                summary: "重点关注 settings.json、会话目录与 provider key。",
                coreSectionTitle: "OpenHands 配置",
                coreSectionSubtitle: "settings + conversations",
                credentialKeys: ["OPENHANDS_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: ["OPENHANDS_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["OPENHANDS_MODEL", "model", "default_model"],
                notes: ["uv 安装场景下，需确认 uv tool 的 bin 目录已加入 PATH。"]
            )
        case .continueCLI:
            return ToolProfile(
                visualTitle: "Continue CLI 配置总览",
                summary: "重点关注 config.yaml、permissions 与 provider 认证。",
                coreSectionTitle: "Continue 配置",
                coreSectionSubtitle: "模型路由 + 权限策略",
                credentialKeys: ["CONTINUE_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "api_key"],
                endpointKeys: ["CONTINUE_BASE_URL", "OPENAI_BASE_URL", "ANTHROPIC_BASE_URL", "base_url"],
                modelKeys: ["CONTINUE_MODEL", "model", "default_model"],
                notes: ["故障定位建议优先查看 ~/.continue/logs/cn.log。"]
            )
        case .amp:
            return ToolProfile(
                visualTitle: "Amp CLI 配置总览",
                summary: "重点关注 AGENTS.md、认证令牌与模型偏好。",
                coreSectionTitle: "Amp 运行配置",
                coreSectionSubtitle: "CLI + AGENTS.md 驱动",
                credentialKeys: ["AMP_API_KEY", "SOURCEGRAPH_ACCESS_TOKEN", "api_key"],
                endpointKeys: ["AMP_BASE_URL", "SRC_ENDPOINT", "base_url"],
                modelKeys: ["AMP_MODEL", "model", "default_model"],
                notes: ["建议把 ~/.config/amp/AGENTS.md 纳入版本控制或备份。"]
            )
        case .kiro:
            return ToolProfile(
                visualTitle: "Kiro CLI 配置总览",
                summary: "重点关注账号登录态与本地路径初始化。",
                coreSectionTitle: "Kiro 运行配置",
                coreSectionSubtitle: "账号态 + 本地配置",
                credentialKeys: ["KIRO_API_KEY", "api_key"],
                endpointKeys: ["KIRO_BASE_URL", "base_url"],
                modelKeys: ["KIRO_MODEL", "model", "default_model"],
                notes: ["若字段未检出，通常需要先在官方 CLI 完成首次登录初始化。"]
            )
        case .cody:
            return ToolProfile(
                visualTitle: "Cody CLI 配置总览",
                summary: "重点关注 Sourcegraph endpoint、token 与默认模型。",
                coreSectionTitle: "Sourcegraph 配置",
                coreSectionSubtitle: "企业实例 / 云端实例兼容",
                credentialKeys: ["SRC_ACCESS_TOKEN", "CODY_API_KEY", "api_key"],
                endpointKeys: ["SRC_ENDPOINT", "CODY_BASE_URL", "base_url"],
                modelKeys: ["CODY_MODEL", "model", "default_model"],
                notes: ["私有部署场景请确认 endpoint 证书和网络连通性。"]
            )
        case .qwenCode:
            return ToolProfile(
                visualTitle: "Qwen Code 配置总览",
                summary: "重点关注 settings.json 与多协议 provider 凭据。",
                coreSectionTitle: "Qwen 兼容协议配置",
                coreSectionSubtitle: "OpenAI / Anthropic / Gemini",
                credentialKeys: ["OPENAI_API_KEY", "QWEN_API_KEY", "ANTHROPIC_API_KEY", "GEMINI_API_KEY", "api_key"],
                endpointKeys: ["OPENAI_BASE_URL", "QWEN_BASE_URL", "base_url"],
                modelKeys: ["QWEN_MODEL", "model", "default_model"],
                notes: ["若启用 OpenAI 兼容网关，请校验模型名与网关供应商对应关系。"]
            )
        }
    }
}
