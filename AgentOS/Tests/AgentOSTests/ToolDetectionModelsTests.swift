import Foundation
import Testing
@testable import AgentOS

struct ToolDetectionModelsTests {
    @Test
    func everyToolHasOfficialWebsiteURL() {
        for tool in ProgrammingTool.allCases {
            let value = tool.officialWebsiteURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(value != nil, "\(tool.id) 缺少官网地址")
            #expect(!(value?.isEmpty ?? true), "\(tool.id) 官网地址不能为空")
        }
    }

    @Test
    func officialWebsiteURLsAreValidHTTPURLs() {
        for tool in ProgrammingTool.allCases {
            validateHTTPURL(tool.officialWebsiteURL, toolID: tool.id, label: "官网")
        }
    }

    @Test
    func everyToolHasDocumentationAndCommunityLinks() {
        for tool in ProgrammingTool.allCases {
            let docs = tool.officialDocumentationURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            let community = tool.officialCommunityURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(docs != nil, "\(tool.id) 缺少文档地址")
            #expect(!(docs?.isEmpty ?? true), "\(tool.id) 文档地址不能为空")
            #expect(community != nil, "\(tool.id) 缺少社区地址")
            #expect(!(community?.isEmpty ?? true), "\(tool.id) 社区地址不能为空")
        }
    }

    @Test
    func officialDocumentationAndCommunityURLsAreValidHTTPURLs() {
        for tool in ProgrammingTool.allCases {
            validateHTTPURL(tool.officialDocumentationURL, toolID: tool.id, label: "文档")
            validateHTTPURL(tool.officialCommunityURL, toolID: tool.id, label: "社区")
        }
    }

    @Test
    func strictDirectConfigEditingPolicyIsApplied() {
        for tool in ProgrammingTool.allCases {
            let expected = (tool == .codex || tool == .claudeCode)
            #expect(tool.supportsDirectConfigEditing == expected, "\(tool.id) 的编辑策略不符合严格模式")
            #expect(tool.supportedEditableFields.isEmpty != expected)
        }
    }

    private func validateHTTPURL(_ rawValue: String?, toolID: String, label: String) {
        guard let raw = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            Issue.record("\(toolID) 缺少\(label)地址")
            return
        }

        let normalized = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: normalized) else {
            Issue.record("\(toolID) \(label)地址非法: \(raw)")
            return
        }

        #expect(url.scheme == "https" || url.scheme == "http")
        #expect(url.host != nil)
    }
}
