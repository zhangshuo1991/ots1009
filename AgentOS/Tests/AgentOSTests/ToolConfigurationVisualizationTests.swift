import Foundation
import Testing
@testable import AgentOS

struct ToolConfigurationVisualizationTests {
    @Test
    func codexVisualizationLoadsTomlAndAuthFromDirectory() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let configDirectory = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let configTOML = configDirectory.appendingPathComponent("config.toml")
        let authJSON = configDirectory.appendingPathComponent("auth.json")

        try """
        model_provider = "codex"
        model = "gpt-5.3-codex"

        [model_providers.codex]
        base_url = "https://example.com/codex/v1"
        """
            .data(using: .utf8)?
            .write(to: configTOML)

        try """
        {"OPENAI_API_KEY":"sk-test-1234567890"}
        """
            .data(using: .utf8)?
            .write(to: authJSON)

        let visualization = ToolConfigurationVisualizationBuilder.build(
            tool: .codex,
            configService: ConfigEditorService(),
            fileManager: .default,
            environment: [:],
            configPathCandidates: [configDirectory.path]
        )

        let allItems = visualization.sections.flatMap(\.items)
        let credential = allItems.first(where: { $0.id == "credential" })
        let model = allItems.first(where: { $0.id == "model" })
        let endpoint = allItems.first(where: { $0.id == "endpoint" })

        #expect(credential != nil)
        #expect(credential?.state == .configured)
        #expect(credential?.value.contains("sk-t") == true)

        #expect(model?.value == "gpt-5.3-codex")
        #expect(model?.state == .configured)

        #expect(endpoint?.value == "https://example.com/codex/v1")
        #expect(endpoint?.state == .configured)
    }

    @Test
    func claudeVisualizationLoadsAuthTokenFromSettingsEnv() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsPath = root.appendingPathComponent("settings.json")
        try """
        {
          "model": "claude-sonnet-4-5",
          "env": {
            "ANTHROPIC_AUTH_TOKEN": "sk-test-anthropic-token-1234",
            "ANTHROPIC_BASE_URL": "https://example.anthropic-proxy.dev"
          }
        }
        """
            .data(using: .utf8)?
            .write(to: settingsPath)

        let visualization = ToolConfigurationVisualizationBuilder.build(
            tool: .claudeCode,
            configService: ConfigEditorService(),
            fileManager: .default,
            environment: [:],
            configPathCandidates: [settingsPath.path]
        )

        let allItems = visualization.sections.flatMap(\.items)
        let credential = allItems.first(where: { $0.id == "credential" })
        let endpoint = allItems.first(where: { $0.id == "endpoint" })
        let model = allItems.first(where: { $0.id == "model" })

        #expect(credential?.state == .configured)
        #expect(credential?.value.contains("sk-t") == true)
        #expect(endpoint?.value == "https://example.anthropic-proxy.dev")
        #expect(model?.value == "claude-sonnet-4-5")
    }

    @Test
    func unsupportedToolVisualizationDoesNotShowEditableThreeParameters() {
        let visualization = ToolConfigurationVisualizationBuilder.build(
            tool: .cursor,
            configService: ConfigEditorService(),
            environment: [:]
        )

        let allItems = visualization.sections.flatMap(\.items)
        #expect(allItems.contains(where: { $0.id == "managed-mode" }))
        #expect(!allItems.contains(where: { $0.id == "credential" }))
        #expect(!allItems.contains(where: { $0.id == "model" }))
        #expect(!allItems.contains(where: { $0.id == "endpoint" }))
    }
}
