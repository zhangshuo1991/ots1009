import Observation
import SwiftUI

struct CLIRuntimePanelView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CLI 运行时接入")
                    .font(.headline)
                Spacer()
                Button("刷新检测") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.refreshCLIStatuses()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("应用已检测命令") {
                    withAnimation(.snappy(duration: 0.2)) {
                        viewModel.applyDetectedBinariesToTemplates()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if viewModel.cliStatuses.isEmpty {
                Text("尚未检测 CLI，可点击“刷新检测”。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.cliStatuses) { status in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(status.isInstalled ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                                .padding(.top, 5)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(status.tool.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(status.isInstalled ? "已安装" : "未安装")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((status.isInstalled ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                                }
                                if let path = status.resolvedBinary {
                                    Text(path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if let version = status.version {
                                    Text(version)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(status.guidance)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .cardSurface()
    }
}
