import Foundation
import Testing
@testable import AgentOS

struct ConfigEditorServiceTests {
    @Test
    func codexEditableConfigRoundTripStillWorksInStrictMode() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ConfigEditorService(fileManager: .default, homeDirectory: root.path)
        let expected = ToolEditableConfig(
            apiKey: "sk-codex-123456",
            baseURL: "https://api.openai-proxy.dev/v1",
            model: "gpt-5-codex"
        )

        try service.saveEditableConfig(expected, for: .codex)
        let loaded = service.loadEditableConfigSync(for: .codex)

        #expect(loaded?.apiKey == expected.apiKey)
        #expect(loaded?.baseURL == expected.baseURL)
        #expect(loaded?.model == expected.model)

        let editablePaths = service.editableConfigPaths(for: .codex)
        #expect(editablePaths.count == 2)
        for path in editablePaths {
            #expect(FileManager.default.fileExists(atPath: path))
        }
    }

    @Test
    func unsupportedToolCannotBeEditedInStrictMode() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ConfigEditorService(fileManager: .default, homeDirectory: root.path)
        #expect(!service.isEditable(tool: .cursor))
        #expect(service.editableConfigPaths(for: .cursor).isEmpty)
        #expect(service.loadEditableConfigSync(for: .cursor) == nil)

        #expect(throws: ConfigEditorError.self) {
            try service.saveEditableConfig(
                ToolEditableConfig(apiKey: "sk-test", baseURL: "https://example.com", model: "model-a"),
                for: .cursor
            )
        }
    }

    @Test
    func onlyCodexAndClaudeAreEditableInStrictMode() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ConfigEditorService(fileManager: .default, homeDirectory: root.path)
        for tool in ProgrammingTool.allCases {
            let editable = service.isEditable(tool: tool)
            let expected = (tool == .codex || tool == .claudeCode)
            #expect(editable == expected, "\(tool.id) 的可编辑能力不符合严格模式")
        }
    }
}
