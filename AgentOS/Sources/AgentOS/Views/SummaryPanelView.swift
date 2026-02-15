import Observation
import SwiftUI

struct SummaryPanelView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    var body: some View {
        let metrics = viewModel.metrics(for: task.id)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("复盘总结")
                    .font(.headline)
                Spacer()
                Button("生成总结") {
                    withAnimation(.snappy(duration: 0.22)) {
                        viewModel.generateSummary(taskID: task.id)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("导出报告") {
                    withAnimation(.snappy(duration: 0.22)) {
                        _ = viewModel.exportDeliveryReport(taskID: task.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                metricCard(title: "恢复均时", value: "\(metrics.recoveryAverageSeconds)s", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                metricCard(title: "预算偏差", value: "\(metrics.budgetDeviationPercent)%", systemImage: "chart.line.downtrend.xyaxis")
                metricCard(title: "阶段门通过", value: "\(metrics.validationPassRatePercent)%", systemImage: "checkmark.seal")
            }

            ScrollView {
                Text(task.summary.isEmpty ? "点击“生成总结”后，会输出阶段、预算、风险与下一步建议。" : task.summary)
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.gray.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            .frame(minHeight: 140)
        }
        .cardSurface()
    }

    private func metricCard(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
