import Observation
import SwiftUI

struct RootDashboardView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        NavigationSplitView {
            TaskSidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            Group {
                if let selectedTask = viewModel.selectedTask {
                    TaskDetailView(viewModel: viewModel, task: selectedTask)
                } else {
                    ContentUnavailableView(
                        "暂无任务",
                        systemImage: "tray",
                        description: Text("点击左侧“新建任务”开始多代理协同执行。")
                    )
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 0.99),
                        Color(red: 0.98, green: 0.98, blue: 0.98),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Agent OS")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("多代理协同 · 任务闭环 · 成本治理")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Label("系统状态", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.globalMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}
