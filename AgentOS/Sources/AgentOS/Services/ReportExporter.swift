import Foundation

struct DeliveryReport: Codable {
    var taskID: UUID
    var title: String
    var generatedAt: Date
    var executionMode: ExecutionMode
    var phase: TaskPhase
    var status: TaskStatus
    var metrics: DeliveryMetrics
    var warnings: [String]
    var summary: String
}

struct DeliveryReportOutput {
    var markdownURL: URL
    var jsonURL: URL
}

final class ReportExporter {
    private let encoder: JSONEncoder

    init() {
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func export(report: DeliveryReport) throws -> DeliveryReportOutput {
        let baseDirectory = try reportsDirectory()
        let stamp = Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")
        let baseName = "\(stamp)-\(report.taskID.uuidString.prefix(8))"
        let markdownURL = baseDirectory.appendingPathComponent("\(baseName).md")
        let jsonURL = baseDirectory.appendingPathComponent("\(baseName).json")

        let markdown = buildMarkdown(report: report)
        try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
        let json = try encoder.encode(report)
        try json.write(to: jsonURL, options: .atomic)

        return DeliveryReportOutput(markdownURL: markdownURL, jsonURL: jsonURL)
    }

    private func reportsDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = appSupport.appendingPathComponent("AgentOS/reports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func buildMarkdown(report: DeliveryReport) -> String {
        let warningBody = report.warnings.isEmpty ? "- 无告警" : report.warnings.map { "- \($0)" }.joined(separator: "\n")
        return """
        # AgentOS 交付报告

        - 任务ID: \(report.taskID.uuidString)
        - 任务标题: \(report.title)
        - 生成时间: \(report.generatedAt.formatted(date: .abbreviated, time: .standard))
        - 执行模式: \(report.executionMode.title)
        - 阶段: \(report.phase.title)
        - 状态: \(report.status.rawValue)

        ## 指标
        - 平均恢复时长: \(report.metrics.recoveryAverageSeconds)s
        - 预算偏差: \(report.metrics.budgetDeviationPercent)%
        - 阶段门通过率: \(report.metrics.validationPassRatePercent)%

        ## 告警
        \(warningBody)

        ## 摘要
        \(report.summary)
        """
    }
}

