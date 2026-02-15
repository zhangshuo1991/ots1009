import SwiftUI

struct BudgetPanelView: View {
    let task: WorkTask
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成本与连续性治理")
                .font(.headline)

            usageRow(title: "Token", ratio: task.budget.tokenUsageRatio, detail: "\(task.budget.tokenUsed) / \(task.budget.tokenLimit)")
            usageRow(
                title: "成本",
                ratio: task.budget.costUsageRatio,
                detail: "$\(task.budget.costUsed.formatted(.number.precision(.fractionLength(2)))) / $\(task.budget.costLimit.formatted(.number.precision(.fractionLength(2))))"
            )
            usageRow(title: "时长", ratio: task.budget.runtimeUsageRatio, detail: "\(task.budget.runtimeSeconds)s / \(task.budget.runtimeLimitSeconds)s")

            if warnings.isEmpty {
                Label("预算与配额处于安全区间", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                }
            }
        }
        .cardSurface()
    }

    private func usageRow(title: String, ratio: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: ratio)
                .tint(ratio >= 0.8 ? .red : .blue)
        }
    }
}
