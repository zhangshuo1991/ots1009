import AppKit
import Foundation

struct ToolEditableConfig {
    var apiKey: String
    var baseURL: String
    var model: String
    var extras: [String: String]

    init(
        apiKey: String,
        baseURL: String,
        model: String,
        extras: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.extras = extras
    }

    static let empty = ToolEditableConfig(apiKey: "", baseURL: "", model: "", extras: [:])

    func value(for fieldID: String) -> String {
        switch fieldID {
        case ToolEditableFieldID.apiKey:
            return apiKey
        case ToolEditableFieldID.baseURL:
            return baseURL
        case ToolEditableFieldID.model:
            return model
        default:
            return extras[fieldID] ?? ""
        }
    }

    mutating func setValue(_ value: String, for fieldID: String) {
        switch fieldID {
        case ToolEditableFieldID.apiKey:
            apiKey = value
        case ToolEditableFieldID.baseURL:
            baseURL = value
        case ToolEditableFieldID.model:
            model = value
        default:
            extras[fieldID] = value
        }
    }
}

enum ConfigEditorError: LocalizedError {
    case invalidConfigPath
    case editingNotSupported(tool: ProgrammingTool)

    var errorDescription: String? {
        switch self {
        case .invalidConfigPath:
            return "无法确定可写入的配置路径。"
        case let .editingNotSupported(tool):
            return "\(tool.title) 不支持在本应用直接编辑 API Key/Base URL/模型。"
        }
    }
}

struct ConfigEditorService {
    private let fileManager: FileManager
    private let homeDirectory: String
    private let systemHomeDirectory: String

    init(fileManager: FileManager = .default, homeDirectory: String = NSHomeDirectory()) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.systemHomeDirectory = NSHomeDirectory()
    }

    func isEditable(tool: ProgrammingTool) -> Bool {
        tool.supportsDirectConfigEditing && !editableFieldDescriptors(for: tool).isEmpty
    }

    func editableConfigPaths(for tool: ProgrammingTool) -> [String] {
        guard isEditable(tool: tool) else { return [] }
        switch tool {
        case .codex:
            let directory = resolvedCodexDirectory()
            return [
                "\(directory)/config.toml",
                "\(directory)/auth.json"
            ]
        case .claudeCode:
            return [resolvedClaudeSettingsPath()]
        default:
            return [resolvedGenericEditableConfigPath(for: tool)]
        }
    }

    func loadEditableConfig(for tool: ProgrammingTool) async -> ToolEditableConfig? {
        loadEditableConfigSync(for: tool)
    }

    func loadEditableConfigSync(for tool: ProgrammingTool) -> ToolEditableConfig? {
        guard isEditable(tool: tool) else { return nil }
        switch tool {
        case .codex:
            return loadCodexEditableConfig()
        case .claudeCode:
            return loadClaudeEditableConfig()
        default:
            return loadGenericEditableConfig(for: tool)
        }
    }

    func saveEditableConfig(_ config: ToolEditableConfig, for tool: ProgrammingTool) throws {
        guard isEditable(tool: tool) else {
            throw ConfigEditorError.editingNotSupported(tool: tool)
        }
        switch tool {
        case .codex:
            try saveCodexEditableConfig(config)
        case .claudeCode:
            try saveClaudeEditableConfig(config)
        default:
            try saveGenericEditableConfig(config, for: tool)
        }
    }

    func loadConfig(from path: String) async -> ToolConfig? {
        loadConfigSync(from: path)
    }

    func loadConfigSync(from path: String) -> ToolConfig? {
        let expandedPath = (path as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parseJSONToConfig(json)
            }
        } catch {
            return nil
        }

        return nil
    }

    func saveConfig(_ config: ToolConfig, to path: String) async throws {
        let expandedPath = (path as NSString).expandingTildeInPath
        let directory = (expandedPath as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let json = configToJSON(config)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: expandedPath))
    }

    func openConfigFile(_ path: String) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        return NSWorkspace.shared.open(url)
    }

    func findExistingConfigPath(for tool: ProgrammingTool) -> String? {
        for path in tool.configPaths {
            let expandedPath = resolveToolPath(path)
            if fileManager.fileExists(atPath: expandedPath) {
                return expandedPath
            }
        }
        return nil
    }

    private func loadCodexEditableConfig() -> ToolEditableConfig {
        let directory = resolvedCodexDirectory()
        let authPath = "\(directory)/auth.json"
        let configPath = "\(directory)/config.toml"

        let auth = loadJSONDictionary(from: authPath)
        let apiKey = firstNonEmptyString(
            auth["OPENAI_API_KEY"] as? String,
            auth["api_key"] as? String
        ) ?? ""

        let tomlText = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        let model = parseTOMLValue(tomlText, key: "model") ?? ""
        let baseURL = parseTOMLValue(tomlText, key: "base_url", section: "model_providers.codex") ?? ""

        return ToolEditableConfig(apiKey: apiKey, baseURL: baseURL, model: model)
    }

    private func saveCodexEditableConfig(_ config: ToolEditableConfig) throws {
        let directory = resolvedCodexDirectory(createIfMissing: true)
        let authPath = "\(directory)/auth.json"
        let configPath = "\(directory)/config.toml"

        var auth = loadJSONDictionary(from: authPath)
        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            auth["OPENAI_API_KEY"] = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try saveJSONDictionary(auth, to: authPath)

        var toml = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        if !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toml = upsertTOMLValue(toml, key: "model", value: config.model.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            toml = upsertTOMLValue(
                toml,
                key: "base_url",
                value: config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                section: "model_providers.codex"
            )
        }
        try ensureParentDirectory(of: configPath)
        try toml.data(using: .utf8)?.write(to: URL(fileURLWithPath: configPath))
    }

    private func loadClaudeEditableConfig() -> ToolEditableConfig {
        let settingsPath = resolvedClaudeSettingsPath()
        let dictionary = loadJSONDictionary(from: settingsPath)
        let env = dictionary["env"] as? [String: Any] ?? [:]

        let apiKey = firstNonEmptyString(
            env["ANTHROPIC_AUTH_TOKEN"] as? String,
            env["ANTHROPIC_API_KEY"] as? String,
            dictionary["ANTHROPIC_AUTH_TOKEN"] as? String,
            dictionary["ANTHROPIC_API_KEY"] as? String
        ) ?? ""

        let baseURL = firstNonEmptyString(
            env["ANTHROPIC_BASE_URL"] as? String,
            dictionary["ANTHROPIC_BASE_URL"] as? String
        ) ?? ""

        let model = firstNonEmptyString(
            env["ANTHROPIC_MODEL"] as? String,
            dictionary["model"] as? String,
            dictionary["defaultModel"] as? String
        ) ?? ""

        return ToolEditableConfig(apiKey: apiKey, baseURL: baseURL, model: model)
    }

    private func saveClaudeEditableConfig(_ config: ToolEditableConfig) throws {
        let settingsPath = resolvedClaudeSettingsPath(createIfMissing: true)
        var dictionary = loadJSONDictionary(from: settingsPath)
        var env = dictionary["env"] as? [String: Any] ?? [:]

        if !config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            env["ANTHROPIC_AUTH_TOKEN"] = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            env["ANTHROPIC_BASE_URL"] = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
            env["ANTHROPIC_MODEL"] = model
            dictionary["model"] = model
        }

        dictionary["env"] = env
        try saveJSONDictionary(dictionary, to: settingsPath)
    }

    private func loadGenericEditableConfig(for tool: ProgrammingTool) -> ToolEditableConfig {
        let configPath = resolvedGenericEditableConfigPath(for: tool)
        let dictionary = loadJSONDictionary(from: configPath)
        let env = dictionary["env"] as? [String: Any] ?? [:]
        var merged: [String: Any] = env
        for (key, value) in dictionary {
            merged[key] = value
        }

        let descriptors = editableFieldDescriptors(for: tool)
        var config = ToolEditableConfig.empty

        for descriptor in descriptors {
            let value = firstNonEmptyString(valuesForKeys(descriptor.readKeys, in: merged)) ?? ""
            config.setValue(value, for: descriptor.id)
        }

        // Gracefully fallback to common keys for hand-written configs.
        if config.apiKey.isEmpty || config.model.isEmpty {
            let fallback = parseJSONToConfig(dictionary)
            if config.apiKey.isEmpty {
                config.apiKey = fallback.apiKey
            }
            if config.model.isEmpty {
                config.model = fallback.model
            }
        }

        return config
    }

    private func saveGenericEditableConfig(_ config: ToolEditableConfig, for tool: ProgrammingTool) throws {
        let configPath = resolvedGenericEditableConfigPath(for: tool, createIfMissing: true)
        var dictionary = loadJSONDictionary(from: configPath)
        var env = dictionary["env"] as? [String: Any] ?? [:]

        let descriptors = editableFieldDescriptors(for: tool)
        for descriptor in descriptors {
            upsertDictionaryField(
                trimmedValue: config.value(for: descriptor.id),
                primaryKey: descriptor.primaryKey,
                canonicalKey: descriptor.canonicalKey,
                dictionary: &dictionary,
                env: &env
            )
        }

        dictionary["env"] = env
        try saveJSONDictionary(dictionary, to: configPath)
    }

    private func upsertDictionaryField(
        trimmedValue rawValue: String,
        primaryKey: String,
        canonicalKey: String,
        dictionary: inout [String: Any],
        env: inout [String: Any]
    ) {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            dictionary.removeValue(forKey: canonicalKey)
            dictionary.removeValue(forKey: primaryKey)
            env.removeValue(forKey: primaryKey)
            return
        }

        dictionary[canonicalKey] = value
        env[primaryKey] = value
    }

    private func valuesForKeys(_ keys: [String], in dictionary: [String: Any]) -> [String?] {
        keys.map { key in
            if let value = dictionary[key] as? String {
                return value
            }
            let lowered = key.lowercased()
            if let value = dictionary[lowered] as? String {
                return value
            }
            if let value = dictionary[key.uppercased()] as? String {
                return value
            }
            return nil
        }
    }

    private func editableFieldDescriptors(for tool: ProgrammingTool) -> [ToolEditableFieldDescriptor] {
        tool.supportedEditableFields
    }

    private func resolvedCodexDirectory(createIfMissing: Bool = false) -> String {
        let home = homeDirectory
        let candidates = [
            "\(home)/.codex",
            "\(home)/.config/codex"
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        let fallback = "\(home)/.codex"
        if createIfMissing {
            try? fileManager.createDirectory(atPath: fallback, withIntermediateDirectories: true)
        }
        return fallback
    }

    private func resolvedClaudeSettingsPath(createIfMissing: Bool = false) -> String {
        let home = homeDirectory
        let settingsPath = "\(home)/.claude/settings.json"

        if createIfMissing {
            let directory = (settingsPath as NSString).deletingLastPathComponent
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            if !fileManager.fileExists(atPath: settingsPath) {
                try? "{}".data(using: .utf8)?.write(to: URL(fileURLWithPath: settingsPath))
            }
        }

        return settingsPath
    }

    private func resolvedGenericEditableConfigPath(for tool: ProgrammingTool, createIfMissing: Bool = false) -> String {
        let rawCandidates = tool.configPaths.map(resolveToolPath)
        var existingDirectoryCandidate: String?

        for rawPath in rawCandidates {
            let expandedPath = (rawPath as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                existingDirectoryCandidate = expandedPath
                continue
            }

            if isLikelyStructuredConfigFile(expandedPath) {
                return expandedPath
            }
        }

        let directoryPath = existingDirectoryCandidate
            ?? firstDirectoryLikeCandidate(in: rawCandidates)
            ?? ((rawCandidates.first ?? "\(homeDirectory)/.config/\(tool.rawValue)") as NSString).expandingTildeInPath

        if createIfMissing {
            try? fileManager.createDirectory(atPath: directoryPath, withIntermediateDirectories: true)
        }

        let configPath = URL(fileURLWithPath: directoryPath).appendingPathComponent("config.json").path
        if createIfMissing, !fileManager.fileExists(atPath: configPath) {
            try? "{}".data(using: .utf8)?.write(to: URL(fileURLWithPath: configPath))
        }

        return configPath
    }

    private func firstDirectoryLikeCandidate(in candidates: [String]) -> String? {
        for rawPath in candidates {
            let expandedPath = (rawPath as NSString).expandingTildeInPath
            if !isLikelyStructuredConfigFile(expandedPath) {
                return expandedPath
            }
        }
        return nil
    }

    private func isLikelyStructuredConfigFile(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasSuffix(".json")
            || lowercased.hasSuffix(".toml")
            || lowercased.hasSuffix(".env")
            || lowercased.hasSuffix(".yaml")
            || lowercased.hasSuffix(".yml")
    }

    private func resolveToolPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let prefix = "\(systemHomeDirectory)/"
        guard expanded.hasPrefix(prefix), homeDirectory != systemHomeDirectory else {
            return expanded
        }
        let suffix = expanded.dropFirst(systemHomeDirectory.count)
        return homeDirectory + suffix
    }

    private func parseJSONToConfig(_ json: [String: Any]) -> ToolConfig {
        var config = ToolConfig()

        if let apiKey = firstNonEmptyString(
            json["api_key"] as? String,
            json["apiKey"] as? String,
            json["ANTHROPIC_API_KEY"] as? String,
            json["OPENAI_API_KEY"] as? String
        ) {
            config.apiKey = apiKey
        }

        if let httpProxy = firstNonEmptyString(
            json["http_proxy"] as? String,
            json["HTTP_PROXY"] as? String
        ) {
            config.httpProxy = httpProxy
        }
        if let httpsProxy = firstNonEmptyString(
            json["https_proxy"] as? String,
            json["HTTPS_PROXY"] as? String
        ) {
            config.httpsProxy = httpsProxy
        }

        if let model = firstNonEmptyString(
            json["model"] as? String,
            json["default_model"] as? String
        ) {
            config.model = model
        }

        return config
    }

    private func configToJSON(_ config: ToolConfig) -> [String: Any] {
        var json: [String: Any] = [:]

        if !config.apiKey.isEmpty {
            json["api_key"] = config.apiKey
        }
        if !config.httpProxy.isEmpty {
            json["http_proxy"] = config.httpProxy
        }
        if !config.httpsProxy.isEmpty {
            json["https_proxy"] = config.httpsProxy
        }
        if !config.model.isEmpty {
            json["model"] = config.model
        }

        return json
    }

    private func firstNonEmptyString(_ candidates: String?...) -> String? {
        for value in candidates {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func firstNonEmptyString(_ candidates: [String?]) -> String? {
        for value in candidates {
            guard let value else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func loadJSONDictionary(from path: String) -> [String: Any] {
        let expanded = (path as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: expanded) else { return [:] }
        guard let data = fileManager.contents(atPath: expanded) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private func saveJSONDictionary(_ dictionary: [String: Any], to path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        try ensureParentDirectory(of: expanded)
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: expanded))
    }

    private func ensureParentDirectory(of path: String) throws {
        let parent = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: parent, withIntermediateDirectories: true)
    }

    private func parseTOMLValue(_ content: String, key: String, section: String? = nil) -> String? {
        let lines = content.components(separatedBy: .newlines)
        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                continue
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            if currentSection == section || (section == nil && currentSection == nil) {
                guard trimmed.hasPrefix("\(key) =") else { continue }
                let raw = trimmed.split(separator: "=", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
                return raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }

        return nil
    }

    private func upsertTOMLValue(_ content: String, key: String, value: String, section: String? = nil) -> String {
        var lines = content.components(separatedBy: .newlines)

        if section == nil {
            var currentSection: String?
            for index in lines.indices {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    currentSection = String(trimmed.dropFirst().dropLast())
                    continue
                }
                if currentSection == nil && trimmed.hasPrefix("\(key) =") {
                    lines[index] = "\(key) = \"\(value)\""
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert("\(key) = \"\(value)\"", at: 0)
            return lines.joined(separator: "\n")
        }

        guard let section else { return lines.joined(separator: "\n") }

        var sectionStart: Int?
        var sectionEnd = lines.count
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed == "[\(section)]" {
                sectionStart = index
                continue
            }
            if sectionStart != nil, trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                sectionEnd = index
                break
            }
        }

        if let sectionStart {
            for index in (sectionStart + 1)..<sectionEnd {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key) =") {
                    lines[index] = "\(key) = \"\(value)\""
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert("\(key) = \"\(value)\"", at: sectionEnd)
            return lines.joined(separator: "\n")
        }

        if !lines.isEmpty, !lines.last!.isEmpty {
            lines.append("")
        }
        lines.append("[\(section)]")
        lines.append("\(key) = \"\(value)\"")
        return lines.joined(separator: "\n")
    }
}
