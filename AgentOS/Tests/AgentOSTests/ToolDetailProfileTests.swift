import Testing
@testable import AgentOS

struct ToolDetailProfileTests {
    @Test
    func geminiProfileContainsVertexFields() {
        let profile = ProgrammingTool.geminiCLI.detailProfile
        let fieldIDs = Set(profile.editableFields.map(\.id))

        #expect(fieldIDs.contains(ToolEditableFieldID.googleCloudProject))
        #expect(fieldIDs.contains(ToolEditableFieldID.googleCloudLocation))
    }

    @Test
    func detailProfilesAreNotSingleTemplate() {
        let signatures = Set(
            ProgrammingTool.allCases.map { tool in
                let ids = tool.detailProfile.editableFields.map(\.id).joined(separator: "|")
                return "\(tool.detailProfile.roleTitle)#\(ids)"
            }
        )

        #expect(signatures.count > 6)
    }
}
