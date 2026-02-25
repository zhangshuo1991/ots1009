import SwiftUI

struct ToolCardView: View {
    let installation: ToolInstallation
    let onSettingsTap: () -> Void
    let onOpenConfigDir: () -> Void
    let onOpenInstallDir: () -> Void
    let onUpdate: () -> Void
    let onUninstall: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                // Status indicator with glow
                ZStack {
                    Circle()
                        .fill(installation.isInstalled ?
                              Color.green.opacity(0.3) :
                              Color.orange.opacity(0.3))
                        .frame(width: 36, height: 36)

                    Circle()
                        .fill(installation.isInstalled ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                        .shadow(color: installation.isInstalled ? .green : .orange, radius: 4)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(installation.tool.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if installation.isInstalled {
                        Text(installation.installMethod.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Status badge
                statusBadge

                // Settings menu
                Menu {
                    Button {
                        onOpenConfigDir()
                    } label: {
                        Label("配置目录", systemImage: "folder")
                    }

                    if installation.isInstalled {
                        Button {
                            onOpenInstallDir()
                        } label: {
                            Label("安装目录", systemImage: "externaldrive")
                        }
                        Divider()
                        Button {
                            onUpdate()
                        } label: {
                            Label("检查更新", systemImage: "arrow.down.circle")
                        }
                        Button(role: .destructive) {
                            onUninstall()
                        } label: {
                            Label("卸载", systemImage: "trash")
                        }
                    }

                    Divider()
                    Button {
                        onSettingsTap()
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .menuStyle(.borderlessButton)
            }

            // Details section
            if installation.isInstalled {
                VStack(alignment: .leading, spacing: 8) {
                    // Path
                    if let path = installation.binaryPath {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // Version and method
                    HStack {
                        if let version = installation.version {
                            Label(version, systemImage: "tag")
                        }

                        Spacer()

                        // Quick action buttons
                        HStack(spacing: 6) {
                            actionButton(icon: "folder", label: "配置", action: onOpenConfigDir)

                            if installation.installLocation != nil {
                                actionButton(icon: "externaldrive", label: "安装", action: onOpenInstallDir)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                // Install hint for uninstalled tools
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text(installation.tool.installHint)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(installation.isInstalled ? Color.green : Color.orange)
                .frame(width: 6, height: 6)

            Text(installation.isInstalled ? "已安装" : "未安装")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            installation.isInstalled ?
            Color.green.opacity(0.15) :
            Color.orange.opacity(0.15)
        )
        .foregroundStyle(installation.isInstalled ? .green : .orange)
        .clipShape(Capsule())
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
