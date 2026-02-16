import SwiftUI

struct ToolCardView: View {
    let installation: ToolInstallation
    let onSettingsTap: () -> Void
    let onOpenConfigDir: () -> Void
    let onOpenInstallDir: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    @State private var isHovering = false
    @State private var showingMenu = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Circle()
                    .fill(installation.isInstalled ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)

                Text(installation.tool.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if installation.isInstalled {
                    Text("已安装")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.2), in: Capsule())
                } else {
                    Text("未安装")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.2), in: Capsule())
                }

                Button {
                    onSettingsTap()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)

                Menu {
                    Button("查看配置") { onOpenConfigDir() }
                    if installation.isInstalled {
                        Button("查看安装目录") { onOpenInstallDir() }
                        Divider()
                        Button("检查更新") { onUpdate() }
                        Button("卸载", role: .destructive) { onUninstall() }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            // Details
            if installation.isInstalled {
                if let path = installation.binaryPath {
                    Text(path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    if let version = installation.version {
                        Text("版本: \(version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(installation.installMethod.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        onOpenConfigDir()
                    } label: {
                        Label("配置目录", systemImage: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if installation.installLocation != nil {
                        Button {
                            onOpenInstallDir()
                        } label: {
                            Label("安装目录", systemImage: "externaldrive")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                Text(installation.tool.installHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.85), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}
