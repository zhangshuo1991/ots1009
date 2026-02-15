import Foundation

struct WorkspaceSnapshot: Codable {
    var tasks: [WorkTask]
    var projects: [WorkspaceProject]?
    var selectedProjectID: UUID?
    var strategyProfiles: [StrategyProfile]
    var selectedStrategyID: UUID?
    var commandTemplates: [String: String]
    var executionMode: ExecutionMode?
    var cliStatuses: [CLIToolStatus]?
    var updatedAt: Date

    init(
        tasks: [WorkTask],
        projects: [WorkspaceProject]? = nil,
        selectedProjectID: UUID? = nil,
        strategyProfiles: [StrategyProfile],
        selectedStrategyID: UUID?,
        commandTemplates: [String: String],
        executionMode: ExecutionMode?,
        cliStatuses: [CLIToolStatus]? = nil,
        updatedAt: Date
    ) {
        self.tasks = tasks
        self.projects = projects
        self.selectedProjectID = selectedProjectID
        self.strategyProfiles = strategyProfiles
        self.selectedStrategyID = selectedStrategyID
        self.commandTemplates = commandTemplates
        self.executionMode = executionMode
        self.cliStatuses = cliStatuses
        self.updatedAt = updatedAt
    }
}

final class SessionPersistence {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = SessionPersistence.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func save(_ snapshot: WorkspaceSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func load() throws -> WorkspaceSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(WorkspaceSnapshot.self, from: data)
    }

    static func defaultFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("AgentOS", isDirectory: true)
            .appendingPathComponent("workspace-snapshot.json")
    }
}
