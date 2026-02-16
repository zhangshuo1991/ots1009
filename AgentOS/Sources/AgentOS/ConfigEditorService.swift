import Foundation
import AppKit

struct ConfigEditorService {

    func loadConfig(from path: String) async -> ToolConfig? {
        let expandedPath = (path as NSString).expandingTildeInPath

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return parseJSONToConfig(json)
            }
        } catch {
            print("Error loading config: \(error)")
        }

        return nil
    }

    func saveConfig(_ config: ToolConfig, to path: String) async throws {
        let expandedPath = (path as NSString).expandingTildeInPath

        // Ensure directory exists
        let directory = (expandedPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

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
            let expandedPath = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                return path
            }
        }
        return nil
    }

    private func parseJSONToConfig(_ json: [String: Any]) -> ToolConfig {
        var config = ToolConfig()

        // Try common API key patterns
        if let apiKey = json["api_key"] as? String ?? json["apiKey"] as? String ?? json["ANTHROPIC_API_KEY"] as? String {
            config.apiKey = apiKey
        }

        // Proxy settings
        if let httpProxy = json["http_proxy"] as? String ?? json["HTTP_PROXY"] as? String {
            config.httpProxy = httpProxy
        }
        if let httpsProxy = json["https_proxy"] as? String ?? json["HTTPS_PROXY"] as? String {
            config.httpsProxy = httpsProxy
        }

        // Model
        if let model = json["model"] as? String ?? json["default_model"] as? String {
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
}
