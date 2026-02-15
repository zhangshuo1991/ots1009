import Observation
import SwiftUI

struct StrategyPanelView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("执行策略")
                .font(.headline)

            Picker("策略", selection: Binding(
                get: { viewModel.selectedStrategy.id },
                set: { viewModel.setStrategy($0) }
            )) {
                ForEach(viewModel.strategyProfiles) { strategy in
                    Text(strategy.name).tag(strategy.id)
                }
            }
            .pickerStyle(.segmented)

            Picker("执行模式", selection: Binding(
                get: { viewModel.executionMode },
                set: { viewModel.setExecutionMode($0) }
            )) {
                ForEach(ExecutionMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(viewModel.selectedStrategy.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label("并发代理: \(viewModel.selectedStrategy.maxParallelAgents)", systemImage: "square.stack.3d.up")
                Label(viewModel.selectedStrategy.autoAdvance ? "自动推进" : "手动推进", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cardSurface()
    }
}
