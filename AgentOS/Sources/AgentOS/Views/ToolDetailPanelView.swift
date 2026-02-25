import AppKit
import SwiftUI

struct ToolDetailPanelView: View {
    let installation: ToolInstallation
    let detailProfile: ToolDetailProfile
    let operationStatus: String
    let configurationVisualization: ToolConfigurationVisualization
    let supportsConfigEditing: Bool
    let updateCheckResult: ToolUpdateCheckResult?
    let isCheckingUpdate: Bool
    let isUpdating: Bool
    let isInstalling: Bool
    let isRepairingNpmCache: Bool
    let operationLogs: [String]
    let isOperationRunning: Bool
    let selectionSummary: String
    let canSelectPrevious: Bool
    let canSelectNext: Bool
    let onSelectPrevious: () -> Void
    let onSelectNext: () -> Void
    let onOpenConfig: () -> Void
    let onOpenConfigDir: () -> Void
    let onOpenInstallDir: () -> Void
    let onRefresh: () -> Void
    let onCheckUpdate: () -> Void
    let onInstall: () -> Void
    let onInstallWithMethod: (InstallMethod) -> Void
    let onUpdate: () -> Void
    let onRepairNpmCache: () -> Void
    let onUninstall: () -> Void
    let terminalSessions: [CLITerminalSession]
    let onCreateTerminalSession: () -> Void
    let onOpenTerminalWorkspace: () -> Void
    let onCloseLatestTerminalSession: () -> Void

    @State private var editableConfig = ToolEditableConfig.empty
    @State private var editableConfigStatus = ""
    @State private var isSavingEditableConfig = false

    private let configService = ConfigEditorService()

    private var editableFields: [ToolEditableFieldDescriptor] {
        installation.tool.supportedEditableFields
    }

    private var supportedInstallMethods: [InstallMethod] {
        installation.tool.preferredInstallMethods.filter { $0 != .unknown }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !operationStatus.isEmpty {
                        infoBanner
                    }

                    brandHeroSection
                    overviewSection
                    actionSection
                    pathSection
                    configPathsSection
                    importantConfigurationSection
                    operationLogsSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            loadEditableConfig()
        }
        .onChange(of: installation.tool) { _, _ in
            loadEditableConfig()
        }
    }

    private var headerBar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(installation.isInstalled ? DesignTokens.ColorToken.statusSuccess : DesignTokens.ColorToken.statusWarning)
                    .frame(width: 8, height: 8)

                HStack(spacing: 7) {
                    Text(installation.tool.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DesignTokens.ColorToken.textPrimary)

                    badge(text: installation.isInstalled ? "已安装" : "未安装", tint: installation.isInstalled ? DesignTokens.ColorToken.statusSuccess : DesignTokens.ColorToken.statusWarning)
                    badge(text: installation.installMethod.title, tint: DesignTokens.ColorToken.statusInfo)
                }
            }

            Spacer()

            HStack(spacing: 7) {
                HStack(spacing: 3) {
                    Text(selectionSummary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                        .padding(.leading, 6)

                    Button(action: onSelectPrevious) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(DesignTokens.ColorToken.panelBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                    )
                    .disabled(!canSelectPrevious)

                    Button(action: onSelectNext) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(DesignTokens.ColorToken.panelBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                    )
                    .disabled(!canSelectNext)
                    .padding(.trailing, 2)
                }
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                )

                Button {
                    onRefresh()
                } label: {
                    Label("刷新检测", systemImage: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                .background(DesignTokens.ColorToken.panelBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(DesignTokens.ColorToken.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.ColorToken.borderDefault)
                .frame(height: 1)
        }
    }

    private var infoBanner: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.statusInfo)

            Text(operationStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.ColorToken.statusInfo)
                .lineLimit(2)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.ColorToken.statusInfo.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.ColorToken.statusInfo.opacity(0.15), lineWidth: 1)
        )
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("概览")

            HStack(spacing: 0) {
                overviewCell(
                    title: "安装状态",
                    value: installation.isInstalled ? "可用" : "未检测到",
                    icon: installation.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    valueColor: installation.isInstalled ? DesignTokens.ColorToken.statusSuccess : DesignTokens.ColorToken.statusWarning
                )
                verticalDivider
                overviewCell(
                    title: "安装方式",
                    value: installation.installMethod.title,
                    icon: "terminal",
                    valueColor: DesignTokens.ColorToken.textPrimary
                )
                verticalDivider
                overviewCell(
                    title: "版本",
                    value: installation.version ?? "未知",
                    icon: "tag",
                    valueColor: DesignTokens.ColorToken.textPrimary,
                    monospaced: true
                )
                verticalDivider
                overviewCell(
                    title: "配置路径",
                    value: "\(installation.configPaths.count) 个位置",
                    icon: "folder",
                    valueColor: DesignTokens.ColorToken.textPrimary
                )
            }
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 6) {
                metadataRow(
                    title: "检测命令",
                    icon: "terminal",
                    value: installation.tool.candidates.joined(separator: " / ")
                )
                installMethodActionRow
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var pathSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("路径详情")

            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    pathField(
                        label: "可执行文件",
                        icon: "terminal",
                        value: installation.binaryPath ?? "未找到可执行路径",
                        buttonIcon: "doc.on.doc",
                        buttonAction: {
                            copyToPasteboard(installation.binaryPath ?? "")
                        }
                    )

                    pathField(
                        label: "安装目录",
                        icon: "folder",
                        value: installation.installLocation ?? "未找到安装目录",
                        buttonIcon: "arrow.up.forward.app",
                        buttonAction: onOpenInstallDir
                    )
                }

                if !installation.isInstalled {
                    Text(installation.tool.installHint)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var brandHeroSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("品牌入口")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    ToolBrandLogoView(
                        primaryLogoURL: primaryLogoURL,
                        fallbackLogoURL: fallbackLogoURL,
                        fallbackSymbol: brandStyle.logoSymbol,
                        fallbackBackgroundStart: brandStyle.gradientStart,
                        fallbackBackgroundEnd: brandStyle.gradientEnd
                    )
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(detailProfile.roleTitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(DesignTokens.ColorToken.textPrimary)
                            .lineLimit(1)

                        Text(detailProfile.roleSubtitle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.ColorToken.textMuted)
                            .lineLimit(1)

                        HStack(spacing: 5) {
                            brandMetaPill(icon: "terminal", text: installation.installMethod.title)
                            if installation.isInstalled {
                                brandMetaPill(icon: "checkmark.circle.fill", text: "已安装")
                            } else {
                                brandMetaPill(icon: "xmark.circle.fill", text: "未安装")
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(minimum: 90), spacing: 6),
                        GridItem(.flexible(minimum: 90), spacing: 6),
                        GridItem(.flexible(minimum: 90), spacing: 6)
                    ],
                    spacing: 6
                ) {
                    ForEach(brandResources) { resource in
                        brandResourceButton(resource)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)

                    Text(websiteURL?.absoluteString ?? "官网地址未配置")
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)

                    Button {
                        copyToPasteboard(websiteURL?.absoluteString ?? "")
                    } label: {
                        Label("复制官网", systemImage: "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DesignTokens.ColorToken.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                    )
                    .disabled(websiteURL == nil)
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                brandStyle.gradientStart.opacity(0.08),
                                brandStyle.gradientEnd.opacity(0.05),
                                DesignTokens.ColorToken.panelBackground
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(brandStyle.gradientStart.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private var configPathsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("配置路径")

            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(installation.configPaths.enumerated()), id: \.offset) { index, path in
                        pathField(
                            label: configPathTitle(for: index),
                            icon: index == 0 ? "person" : "gearshape",
                            value: path,
                            buttonIcon: "doc.on.doc",
                            buttonAction: {
                                copyToPasteboard(path)
                            }
                        )
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var importantConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle(configurationVisualization.title)

            VStack(alignment: .leading, spacing: 8) {
                profileHeaderCard

                Text(configurationVisualization.summary)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)

                if supportsConfigEditing {
                    inlineEditableConfigurationPanel
                }

                if !supportsConfigEditing, !detailProfile.editableFields.isEmpty {
                    readOnlyConfigurationFieldPanel
                }

                ForEach(visibleConfigurationSections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.textSecondary)

                        Text(section.subtitle)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.ColorToken.textMuted)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(section.items) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Image(systemName: stateIcon(for: item.state))
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(stateColor(for: item.state))

                                        Text(item.title)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(DesignTokens.ColorToken.textMuted)
                                            .lineLimit(1)
                                    }

                                    Text(item.value)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(DesignTokens.ColorToken.textPrimary)
                                        .lineLimit(1)

                                    Text(item.detail)
                                        .font(.system(size: 9, weight: .regular))
                                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(DesignTokens.ColorToken.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(stateColor(for: item.state).opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                if !configurationVisualization.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(configurationVisualization.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.ColorToken.textMuted)
                        }
                    }
                }

                if !detailProfile.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("专属诊断提示")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                        ForEach(detailProfile.diagnostics, id: \.self) { tip in
                            Label(tip, systemImage: "stethoscope")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(DesignTokens.ColorToken.textMuted)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("快捷操作")

            VStack(alignment: .leading, spacing: 7) {
                if installation.isInstalled, installation.tool.supportsIntegratedTerminal {
                    terminalWorkspaceQuickActionCard
                }

                HStack(spacing: 6) {
                    if installation.isInstalled {
                        actionButton(
                            title: "打开设置",
                            icon: "slider.horizontal.3",
                            isPrimary: true,
                            isEnabled: supportsConfigEditing,
                            action: onOpenConfig
                        )
                    } else {
                        actionButton(
                            title: isInstalling ? "安装中..." : "安装软件",
                            icon: "arrow.down.circle",
                            isPrimary: true,
                            isEnabled: !isInstalling,
                            action: onInstall
                        )
                    }

                    Rectangle()
                        .fill(DesignTokens.ColorToken.borderDefault)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 1)

                    actionButton(title: "刷新状态", icon: "arrow.clockwise", action: onRefresh)
                    actionButton(title: "配置目录", icon: "folder", action: onOpenConfigDir)
                    actionButton(
                        title: "安装目录",
                        icon: "square.and.arrow.down",
                        isEnabled: installation.installLocation != nil && installation.isInstalled,
                        action: onOpenInstallDir
                    )

                    if installation.isInstalled {
                        actionButton(
                            title: isCheckingUpdate ? "检查中..." : "检查更新",
                            icon: "clock.arrow.circlepath",
                            isEnabled: !isCheckingUpdate && !isUpdating && !isRepairingNpmCache,
                            action: onCheckUpdate
                        )

                        if let updateCheckResult, updateCheckResult.hasUpdate {
                            actionButton(
                                title: isUpdating
                                ? "更新中..."
                                : "更新到 \(updateCheckResult.latestVersion ?? "新版本")",
                                icon: "arrow.up.circle",
                                isPrimary: true,
                                isEnabled: !isUpdating && !isCheckingUpdate && !isRepairingNpmCache,
                                action: onUpdate
                            )
                        }

                        if let updateCheckResult, updateCheckResult.issue == .npmCachePermission {
                            actionButton(
                                title: isRepairingNpmCache ? "修复中..." : "一键修复 npm 缓存权限",
                                icon: "key.fill",
                                isPrimary: true,
                                isEnabled: !isRepairingNpmCache && !isUpdating && !isCheckingUpdate,
                                action: onRepairNpmCache
                            )
                        }

                        Spacer(minLength: 0)

                        actionButton(
                            title: "卸载",
                            icon: "trash",
                            role: .destructive,
                            isEnabled: !isUpdating && !isCheckingUpdate && !isRepairingNpmCache,
                            action: onUninstall
                        )
                    }
                }

                if installation.isInstalled, let updateCheckResult {
                    updateStatusLine(updateCheckResult)
                }

                if !supportsConfigEditing {
                    Text("该工具不支持在本应用直接编辑 API Key / Base URL / 模型，请使用官方客户端或官方配置文件。")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var terminalWorkspaceQuickActionCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("终端工作台")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DesignTokens.ColorToken.textPrimary)

                Text("新会话会在顶部多 Tab 工作台打开，可并行切换。")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)

                Text("当前会话数：\(terminalSessions.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.statusInfo)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    onOpenTerminalWorkspace()
                } label: {
                    Label("打开工作台", systemImage: "rectangle.inset.filled")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.ColorToken.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                )

                if !terminalSessions.isEmpty {
                    Button {
                        onCloseLatestTerminalSession()
                    } label: {
                        Label("关闭会话", systemImage: "xmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignTokens.ColorToken.statusDanger)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.ColorToken.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DesignTokens.ColorToken.statusDanger.opacity(0.3), lineWidth: 1)
                    )
                }

                Button {
                    onCreateTerminalSession()
                } label: {
                    Label("新建终端", systemImage: "plus.rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorToken.textInverse)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignTokens.ColorToken.statusInfo,
                                    DesignTokens.ColorToken.brandPrimary
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DesignTokens.ColorToken.statusInfo.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DesignTokens.ColorToken.statusInfo.opacity(0.28), lineWidth: 1)
        )
    }

    private var operationLogsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionTitle("安装/更新过程")

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOperationRunning ? DesignTokens.ColorToken.statusInfo : DesignTokens.ColorToken.textMuted)
                        .frame(width: 7, height: 7)

                    Text(isOperationRunning ? "命令执行中..." : "等待操作")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            isOperationRunning
                            ? DesignTokens.ColorToken.statusInfo
                            : DesignTokens.ColorToken.textMuted
                        )
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(displayedOperationLogs.indices, id: \.self) { index in
                            Text(displayedOperationLogs[index])
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 64, maxHeight: 120)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.inputBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                )
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
            )
        }
    }

    private var displayedOperationLogs: [String] {
        if operationLogs.isEmpty {
            return ["尚未执行安装/更新命令"]
        }
        return Array(operationLogs.suffix(120))
    }

    private var visibleConfigurationSections: [ConfigurationVisualSection] {
        configurationVisualization.sections.filter { section in
            if section.id.hasPrefix("path-") {
                return false
            }
            if supportsConfigEditing && section.id.hasPrefix("key-") {
                return false
            }
            return true
        }
    }

    private var websiteURL: URL? {
        normalizedURL(from: installation.tool.officialWebsiteURL)
    }

    private var documentationURL: URL? {
        normalizedURL(from: installation.tool.officialDocumentationURL) ?? websiteURL
    }

    private var communityURL: URL? {
        normalizedURL(from: installation.tool.officialCommunityURL) ?? websiteURL
    }

    private var primaryLogoURL: URL? {
        guard let domain = preferredLogoDomain else { return nil }
        return URL(string: "https://logo.clearbit.com/\(domain)")
    }

    private var fallbackLogoURL: URL? {
        guard let domain = preferredLogoDomain else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128")
    }

    private var preferredLogoDomain: String? {
        switch installation.tool {
        case .codex:
            return "openai.com"
        case .claudeCode:
            return "anthropic.com"
        case .kimiCLI:
            return "kimi.com"
        case .opencode:
            return "opencode.ai"
        case .geminiCLI:
            return "google.com"
        case .cursor:
            return "cursor.com"
        case .windsurf:
            return "windsurf.com"
        case .trae:
            return "trae.ai"
        case .kiloCode:
            return "kilocode.ai"
        case .openclaw:
            return "openclaw.ai"
        case .cline:
            return "cline.bot"
        case .rooCode:
            return "roocode.com"
        case .grokCLI:
            return "x.ai"
        case .droid:
            return "droid.dev"
        case .zed:
            return "zed.dev"
        case .monkeyCode:
            return "monkeycode.ai"
        case .githubCopilotCLI:
            return "github.com"
        case .aider:
            return "aider.chat"
        case .goose:
            return "block.xyz"
        case .plandex:
            return "plandex.ai"
        case .openHands:
            return "all-hands.dev"
        case .continueCLI:
            return "continue.dev"
        case .amp:
            return "ampcode.com"
        case .kiro:
            return "kiro.dev"
        case .cody:
            return "sourcegraph.com"
        case .qwenCode:
            return "qwenlm.ai"
        }
    }

    private struct BrandResource: Identifiable {
        let id: String
        let title: String
        let icon: String
        let url: URL?
    }

    private var brandResources: [BrandResource] {
        [
            BrandResource(id: "website", title: "官网", icon: "globe", url: websiteURL),
            BrandResource(id: "docs", title: "文档", icon: "book.closed", url: documentationURL),
            BrandResource(id: "community", title: "社区", icon: "person.3", url: communityURL),
        ]
    }

    private func normalizedURL(from rawValue: String?) -> URL? {
        guard let rawURL = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty else {
            return nil
        }

        if let url = URL(string: rawURL), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(rawURL)")
    }

    private struct ToolBrandStyle {
        let logoSymbol: String
        let gradientStart: Color
        let gradientEnd: Color
    }

    private var brandStyle: ToolBrandStyle {
        switch installation.tool {
        case .codex:
            return ToolBrandStyle(
                logoSymbol: "cpu.fill",
                gradientStart: brandColor(0x0EA5E9),
                gradientEnd: brandColor(0x0284C7)
            )
        case .claudeCode:
            return ToolBrandStyle(
                logoSymbol: "sparkles",
                gradientStart: brandColor(0xF97316),
                gradientEnd: brandColor(0xC2410C)
            )
        case .kimiCLI:
            return ToolBrandStyle(
                logoSymbol: "moon.stars.fill",
                gradientStart: brandColor(0xEF4444),
                gradientEnd: brandColor(0xB91C1C)
            )
        case .opencode:
            return ToolBrandStyle(
                logoSymbol: "chevron.left.forwardslash.chevron.right",
                gradientStart: brandColor(0x06B6D4),
                gradientEnd: brandColor(0x0891B2)
            )
        case .geminiCLI:
            return ToolBrandStyle(
                logoSymbol: "diamond.fill",
                gradientStart: brandColor(0x2563EB),
                gradientEnd: brandColor(0x0F766E)
            )
        case .cursor:
            return ToolBrandStyle(
                logoSymbol: "cursorarrow.rays",
                gradientStart: brandColor(0x374151),
                gradientEnd: brandColor(0x111827)
            )
        case .windsurf:
            return ToolBrandStyle(
                logoSymbol: "wind",
                gradientStart: brandColor(0x10B981),
                gradientEnd: brandColor(0x0F766E)
            )
        case .trae:
            return ToolBrandStyle(
                logoSymbol: "paperplane.fill",
                gradientStart: brandColor(0xF43F5E),
                gradientEnd: brandColor(0xE11D48)
            )
        case .kiloCode:
            return ToolBrandStyle(
                logoSymbol: "bolt.fill",
                gradientStart: brandColor(0xF59E0B),
                gradientEnd: brandColor(0xB45309)
            )
        case .openclaw:
            return ToolBrandStyle(
                logoSymbol: "pawprint.fill",
                gradientStart: brandColor(0xDC2626),
                gradientEnd: brandColor(0x991B1B)
            )
        case .cline:
            return ToolBrandStyle(
                logoSymbol: "link.circle.fill",
                gradientStart: brandColor(0x4B5563),
                gradientEnd: brandColor(0x1F2937)
            )
        case .rooCode:
            return ToolBrandStyle(
                logoSymbol: "hare.fill",
                gradientStart: brandColor(0x22C55E),
                gradientEnd: brandColor(0x15803D)
            )
        case .grokCLI:
            return ToolBrandStyle(
                logoSymbol: "brain.head.profile",
                gradientStart: brandColor(0xFB923C),
                gradientEnd: brandColor(0xC2410C)
            )
        case .droid:
            return ToolBrandStyle(
                logoSymbol: "desktopcomputer",
                gradientStart: brandColor(0x14B8A6),
                gradientEnd: brandColor(0x0F766E)
            )
        case .zed:
            return ToolBrandStyle(
                logoSymbol: "bolt.horizontal.circle.fill",
                gradientStart: brandColor(0x2563EB),
                gradientEnd: brandColor(0x1D4ED8)
            )
        case .monkeyCode:
            return ToolBrandStyle(
                logoSymbol: "hammer.fill",
                gradientStart: brandColor(0xD97706),
                gradientEnd: brandColor(0x92400E)
            )
        case .githubCopilotCLI:
            return ToolBrandStyle(
                logoSymbol: "bolt.circle.fill",
                gradientStart: brandColor(0x2563EB),
                gradientEnd: brandColor(0x1D4ED8)
            )
        case .aider:
            return ToolBrandStyle(
                logoSymbol: "person.crop.circle.badge.checkmark",
                gradientStart: brandColor(0x0EA5E9),
                gradientEnd: brandColor(0x0369A1)
            )
        case .goose:
            return ToolBrandStyle(
                logoSymbol: "bird.fill",
                gradientStart: brandColor(0x0F766E),
                gradientEnd: brandColor(0x115E59)
            )
        case .plandex:
            return ToolBrandStyle(
                logoSymbol: "list.bullet.clipboard.fill",
                gradientStart: brandColor(0x14B8A6),
                gradientEnd: brandColor(0x0F766E)
            )
        case .openHands:
            return ToolBrandStyle(
                logoSymbol: "hands.sparkles.fill",
                gradientStart: brandColor(0x8B5CF6),
                gradientEnd: brandColor(0x6D28D9)
            )
        case .continueCLI:
            return ToolBrandStyle(
                logoSymbol: "arrowtriangle.forward.circle.fill",
                gradientStart: brandColor(0x2563EB),
                gradientEnd: brandColor(0x0284C7)
            )
        case .amp:
            return ToolBrandStyle(
                logoSymbol: "waveform.path.ecg",
                gradientStart: brandColor(0xF97316),
                gradientEnd: brandColor(0xC2410C)
            )
        case .kiro:
            return ToolBrandStyle(
                logoSymbol: "wave.3.forward.circle.fill",
                gradientStart: brandColor(0xEC4899),
                gradientEnd: brandColor(0xBE185D)
            )
        case .cody:
            return ToolBrandStyle(
                logoSymbol: "bubble.left.and.bubble.right.fill",
                gradientStart: brandColor(0xF59E0B),
                gradientEnd: brandColor(0xB45309)
            )
        case .qwenCode:
            return ToolBrandStyle(
                logoSymbol: "aqi.medium",
                gradientStart: brandColor(0x4F46E5),
                gradientEnd: brandColor(0x3730A3)
            )
        }
    }

    private func brandColor(_ hex: UInt) -> Color {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    private struct ToolBrandLogoView: View {
        let primaryLogoURL: URL?
        let fallbackLogoURL: URL?
        let fallbackSymbol: String
        let fallbackBackgroundStart: Color
        let fallbackBackgroundEnd: Color

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [fallbackBackgroundStart, fallbackBackgroundEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                logoContent
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 1)
            )
        }

        @ViewBuilder
        private var logoContent: some View {
            if let primaryLogoURL {
                AsyncImage(url: primaryLogoURL) { phase in
                    switch phase {
                    case .success(let image):
                        renderLogo(image)
                    case .failure:
                        fallbackLogoContent
                    case .empty:
                        fallbackSymbolContent(opacity: 0.92)
                    @unknown default:
                        fallbackLogoContent
                    }
                }
            } else {
                fallbackLogoContent
            }
        }

        @ViewBuilder
        private var fallbackLogoContent: some View {
            if let fallbackLogoURL {
                AsyncImage(url: fallbackLogoURL) { phase in
                    switch phase {
                    case .success(let image):
                        renderLogo(image)
                    default:
                        fallbackSymbolContent(opacity: 0.96)
                    }
                }
            } else {
                fallbackSymbolContent(opacity: 0.96)
            }
        }

        private func renderLogo(_ image: Image) -> some View {
            image
                .resizable()
                .scaledToFit()
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.96))
                        .padding(4)
                )
        }

        private func fallbackSymbolContent(opacity: Double) -> some View {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(opacity))
        }
    }

    private func resourceHostLabel(_ url: URL?) -> String {
        guard let host = url?.host, !host.isEmpty else {
            return "未配置"
        }
        return host
    }

    private func updateStatusLine(_ result: ToolUpdateCheckResult) -> some View {
        HStack(spacing: 6) {
            Image(systemName: updateStatusIcon(result.state))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(updateStatusColor(result.state))
            Text(result.message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(updateStatusColor(result.state))
        }
    }

    private func updateStatusIcon(_ state: ToolUpdateState) -> String {
        switch state {
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private func updateStatusColor(_ state: ToolUpdateState) -> Color {
        switch state {
        case .upToDate:
            return DesignTokens.ColorToken.statusSuccess
        case .updateAvailable:
            return DesignTokens.ColorToken.statusInfo
        case .unknown:
            return DesignTokens.ColorToken.textMuted
        }
    }

    private func metadataRow(title: String, icon: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 92, alignment: .leading)

            Text(value.isEmpty ? "未配置" : value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var installMethodActionRow: some View {
        HStack(alignment: .top, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)

                Text("支持安装方式")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: 92, alignment: .leading)

            if supportedInstallMethods.isEmpty {
                Text("未配置")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 6)], spacing: 6) {
                    ForEach(supportedInstallMethods, id: \.id) { method in
                        installMethodChip(method)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func installMethodChip(_ method: InstallMethod) -> some View {
        let isBusy = isInstalling || isCheckingUpdate || isUpdating || isRepairingNpmCache
        let isEnabled = !installation.isInstalled && !isBusy

        return Button {
            onInstallWithMethod(method)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: installMethodIcon(for: method))
                    .font(.system(size: 9, weight: .semibold))

                Text(installation.isInstalled ? method.title : "安装 \(method.title)")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                installation.isInstalled
                ? DesignTokens.ColorToken.textMuted
                : DesignTokens.ColorToken.textSecondary
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(installation.isInstalled ? DesignTokens.ColorToken.inputBackground : DesignTokens.ColorToken.panelBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        installation.isInstalled
                        ? DesignTokens.ColorToken.borderDefault
                        : DesignTokens.ColorToken.borderStrong,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func installMethodIcon(for method: InstallMethod) -> String {
        switch method {
        case .npm:
            return "shippingbox.fill"
        case .homebrew:
            return "cup.and.saucer.fill"
        case .pip:
            return "drop.fill"
        case .direct:
            return "globe"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var readOnlyConfigurationFieldPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("配置字段映射（只读）")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(detailProfile.editableFields) { field in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.textPrimary)
                            .lineLimit(1)

                        Text(field.helper)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(DesignTokens.ColorToken.textMuted)
                            .lineLimit(2)

                        Text(field.readKeys.joined(separator: " / "))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignTokens.ColorToken.statusInfo)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 6)
                    .background(DesignTokens.ColorToken.inputBackground, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                    )
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.ColorToken.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
        )
    }

    private var inlineEditableConfigurationPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("可直接编辑")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)

            ForEach(editableFields) { field in
                dynamicFieldView(field)
            }

            HStack(spacing: 5) {
                Button("重新读取") {
                    loadEditableConfig()
                }
                .buttonStyle(.bordered)

                Button {
                    saveEditableConfig()
                } label: {
                    Label("保存配置", systemImage: "square.and.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.ColorToken.brandPrimary)
                .disabled(isSavingEditableConfig)
            }

            if !editableConfigStatus.isEmpty {
                Text(editableConfigStatus)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        editableConfigStatus.contains("失败")
                        ? DesignTokens.ColorToken.statusDanger
                        : DesignTokens.ColorToken.statusSuccess
                    )
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
        )
    }

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detailProfile.roleTitle)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DesignTokens.ColorToken.textPrimary)

            Text(detailProfile.roleSubtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            if !detailProfile.capabilityTags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(detailProfile.capabilityTags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.statusInfo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(DesignTokens.ColorToken.statusInfo.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(DesignTokens.ColorToken.statusInfo.opacity(0.18), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
        )
    }

    private func dynamicFieldView(_ field: ToolEditableFieldDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            if field.isSecure {
                SecureField(field.placeholder, text: binding(for: field.id))
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(field.placeholder, text: binding(for: field.id))
                    .textFieldStyle(.roundedBorder)
            }

            if !field.helper.isEmpty {
                Text(field.helper)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
            }
        }
    }

    private func binding(for fieldID: String) -> Binding<String> {
        Binding(
            get: { editableConfig.value(for: fieldID) },
            set: { newValue in
                editableConfig.setValue(newValue, for: fieldID)
            }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(DesignTokens.ColorToken.textSecondary)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(DesignTokens.ColorToken.borderDefault)
            .frame(width: 1)
            .padding(.vertical, 7)
    }

    private func overviewCell(
        title: String,
        value: String,
        icon: String,
        valueColor: Color,
        monospaced: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)

                Text(value)
                    .font(
                        monospaced
                        ? .system(size: 12, weight: .medium, design: .monospaced)
                        : .system(size: 12, weight: .semibold)
                    )
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathField(
        label: String,
        icon: String,
        value: String,
        buttonIcon: String,
        buttonAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)

                Text(value)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                    .lineLimit(1)
                    .textSelection(.enabled)

                Spacer(minLength: 0)

                Button(action: buttonAction) {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                        .padding(5)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DesignTokens.ColorToken.panelBackground)
                )
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DesignTokens.ColorToken.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
            )
        }
    }

    private func brandResourceButton(_ resource: BrandResource) -> some View {
        Button {
            guard let url = resource.url else { return }
            NSWorkspace.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: resource.icon)
                        .font(.system(size: 10, weight: .semibold))

                    Text(resource.title)
                        .font(.system(size: 10, weight: .semibold))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 8, weight: .semibold))
                }

                Text(resourceHostLabel(resource.url))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            resource.url == nil
            ? DesignTokens.ColorToken.textMuted
            : DesignTokens.ColorToken.textSecondary
        )
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    resource.url == nil
                    ? DesignTokens.ColorToken.borderDefault
                    : DesignTokens.ColorToken.borderStrong,
                    lineWidth: 1
                )
        )
        .disabled(resource.url == nil)
    }

    private func brandMetaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DesignTokens.ColorToken.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(DesignTokens.ColorToken.panelBackground.opacity(0.9))
        )
        .overlay(
            Capsule()
                .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        icon: String,
        role: ButtonRole? = nil,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)

        if isPrimary {
            button
                .foregroundStyle(DesignTokens.ColorToken.textInverse)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.brandPrimary)
                )
                .disabled(!isEnabled)
        } else if role == .destructive {
            button
                .foregroundStyle(DesignTokens.ColorToken.statusDanger)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.statusDanger.opacity(0.35), lineWidth: 1)
                )
                .disabled(!isEnabled)
        } else {
            button
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                )
                .disabled(!isEnabled)
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.2), lineWidth: 1)
            )
    }

    private func configPathTitle(for index: Int) -> String {
        switch index {
        case 0:
            return "用户配置"
        case 1:
            return "全局配置"
        default:
            return "配置 \(index + 1)"
        }
    }

    private func stateColor(for state: ConfigurationValueState) -> Color {
        switch state {
        case .configured:
            return DesignTokens.ColorToken.statusSuccess
        case .warning:
            return DesignTokens.ColorToken.statusWarning
        case .missing:
            return DesignTokens.ColorToken.statusDanger
        case .informational:
            return DesignTokens.ColorToken.statusInfo
        }
    }

    private func stateIcon(for state: ConfigurationValueState) -> String {
        switch state {
        case .configured:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .missing:
            return "xmark.octagon.fill"
        case .informational:
            return "info.circle.fill"
        }
    }

    private func copyToPasteboard(_ value: String) {
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func loadEditableConfig() {
        editableConfigStatus = ""
        guard supportsConfigEditing, !editableFields.isEmpty else {
            editableConfig = .empty
            return
        }

        if let loaded = configService.loadEditableConfigSync(for: installation.tool) {
            editableConfig = loaded
        } else {
            editableConfig = .empty
        }
    }

    private func saveEditableConfig() {
        guard supportsConfigEditing, !editableFields.isEmpty else { return }
        isSavingEditableConfig = true
        editableConfigStatus = ""

        do {
            try configService.saveEditableConfig(editableConfig, for: installation.tool)
            editableConfigStatus = "保存成功，已写入配置文件"
            onRefresh()
        } catch {
            editableConfigStatus = "保存失败: \(error.localizedDescription)"
        }

        isSavingEditableConfig = false
    }
}
