import AppKit
import Observation
import SwiftUI

struct MainView: View {
    @Bindable var state: AppState
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var selectedToolID: ProgrammingTool?
    @State private var listScrollPositionID: ProgrammingTool?
    @State private var searchText = ""
    @State private var statusFilter: SidebarFilter = .all
    @State private var detailPage: DetailPage = .toolDetail
    @State private var isTerminalImmersiveMode = false
    @State private var isBatchMode = false
    @State private var batchSelectedTools: Set<ProgrammingTool> = []
    @State private var isSidebarCollapsed = false

    private enum SidebarFilter: String, CaseIterable, Identifiable {
        case all
        case installed
        case missing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all:
                return "全部"
            case .installed:
                return "已安装"
            case .missing:
                return "未安装"
            }
        }

        func matches(_ installation: ToolInstallation) -> Bool {
            switch self {
            case .all:
                return true
            case .installed:
                return installation.isInstalled
            case .missing:
                return !installation.isInstalled
            }
        }
    }

    private enum DetailPage: String, CaseIterable, Identifiable {
        case toolDetail
        case terminalWorkspace

        var id: String { rawValue }

        var title: String {
            switch self {
            case .toolDetail:
                return "软件详情"
            case .terminalWorkspace:
                return "终端工作台"
            }
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.ColorToken.appBackground)
            .sheet(item: $state.selectedToolForConfig) { tool in
                ConfigEditorView(tool: tool)
            }
            .onAppear {
                syncSelectionWithInstallations()
            }
            .onChange(of: filteredInstallations.map(\.id)) { _, newIDs in
                syncSelectionWithInstallations()
                let visibleTools = Set(newIDs)
                batchSelectedTools = batchSelectedTools.intersection(visibleTools)
            }
            .onChange(of: listScrollPositionID) { _, newValue in
                guard let newValue, newValue != selectedToolID else { return }
                selectTool(newValue, syncScrollPosition: false)
            }
            .onChange(of: searchText) { _, _ in
                syncSelectionWithInstallations()
            }
            .onChange(of: statusFilter) { _, _ in
                syncSelectionWithInstallations()
            }
    }

    private var content: some View {
        HStack(spacing: 0) {
            if !shouldHideGlobalChrome {
                if isSidebarCollapsed {
                    collapsedSidebarRail
                } else {
                    sidebar
                }
                Rectangle()
                    .fill(DesignTokens.ColorToken.borderDefault)
                    .frame(width: 1)
            }
            detailPanel
        }
        .animation(.easeInOut(duration: 0.16), value: shouldHideGlobalChrome)
        .animation(.easeInOut(duration: 0.16), value: isSidebarCollapsed)
    }

    private var sidebar: some View {
        let reduceMotion = accessibilityReduceMotion

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("软件目录")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(DesignTokens.ColorToken.textPrimary)

                        Text("先筛选再滚动，右侧详情会实时切换")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    }

                    Spacer(minLength: 0)

                    Button {
                        isSidebarCollapsed = true
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(DesignTokens.ColorToken.panelBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("收缩侧边栏")
                }

                HStack(spacing: 6) {
                    statCard(
                        countText: "\(state.installedToolCount)",
                        label: "已安装",
                        countColor: DesignTokens.ColorToken.statusSuccess
                    )

                    statCard(
                        countText: "\(state.uninstalledToolCount)",
                        label: "未安装",
                        countColor: DesignTokens.ColorToken.statusWarning
                    )

                    Button {
                        refreshAll()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                            Text("刷新")
                                .font(.system(size: 9, weight: .semibold))
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(DesignTokens.ColorToken.brandPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DesignTokens.ColorToken.brandPrimary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(DesignTokens.ColorToken.brandPrimary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleBatchMode()
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: isBatchMode ? "checkmark.circle.fill" : "checklist")
                                .font(.system(size: 14, weight: .semibold))
                            Text("批量")
                                .font(.system(size: 9, weight: .semibold))
                                .textCase(.uppercase)
                        }
                        .foregroundStyle(
                            isBatchMode
                            ? DesignTokens.ColorToken.textInverse
                            : DesignTokens.ColorToken.brandPrimary
                        )
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    isBatchMode
                                    ? DesignTokens.ColorToken.brandPrimary
                                    : DesignTokens.ColorToken.brandPrimary.opacity(0.08)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(DesignTokens.ColorToken.brandPrimary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let installedTools = Set(
                        state.installations.filter(\.isInstalled).map(\.tool)
                    )
                    state.batchCheckUpdates(installedTools)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .semibold))
                        Text("一键检查全部更新")
                            .font(.system(size: 11, weight: .medium))
                        Spacer(minLength: 0)
                        if !state.checkingUpdateTools.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .foregroundStyle(DesignTokens.ColorToken.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(DesignTokens.ColorToken.brandPrimary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(DesignTokens.ColorToken.brandPrimary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!state.checkingUpdateTools.isEmpty)

                searchBar

                statusFilterBar
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if filteredInstallations.isEmpty {
                emptySidebarState
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredInstallations) { installation in
                            ToolSidebarRowView(
                                installation: installation,
                                isSelected: selectedToolID == installation.id,
                                onSelect: {
                                    if isBatchMode {
                                        toggleBatchSelection(installation.tool)
                                    } else {
                                        selectTool(installation.id, syncScrollPosition: true)
                                    }
                                },
                                isBatchMode: isBatchMode,
                                isBatchSelected: batchSelectedTools.contains(installation.tool),
                                onBatchToggle: {
                                    toggleBatchSelection(installation.tool)
                                }
                            )
                            .id(installation.id)
                            .scrollTransition(axis: .vertical) { content, phase in
                                content
                                    .opacity(reduceMotion ? 1 : (phase.isIdentity ? 1 : 0.82))
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollPosition(id: $listScrollPositionID, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
            }

            if isBatchMode && !batchSelectedTools.isEmpty {
                BatchActionBarView(
                    selectedCount: batchSelectedTools.count,
                    installedSelectedCount: installedBatchSelectedCount,
                    hasUpdatingTools: !state.updatingTools.intersection(batchSelectedTools).isEmpty,
                    hasCheckingTools: !state.checkingUpdateTools.intersection(batchSelectedTools).isEmpty,
                    onCheckUpdatesAll: {
                        state.batchCheckUpdates(batchSelectedTools)
                    },
                    onUpdateAll: {
                        state.batchUpdateTools(batchSelectedTools)
                    },
                    onUninstallAll: {
                        state.batchUninstallTools(batchSelectedTools)
                    },
                    onDeselectAll: {
                        batchSelectedTools.removeAll()
                    }
                )
            }

            Spacer(minLength: 2)

            Button {
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Light Theme")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(DesignTokens.ColorToken.panelBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 292)
        .background(DesignTokens.ColorToken.sidebarBackground)
    }

    private var collapsedSidebarRail: some View {
        VStack(spacing: 8) {
            Button {
                isSidebarCollapsed = false
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.ColorToken.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("展开侧边栏")

            Divider()
                .padding(.horizontal, 6)

            Button {
                detailPage = .toolDetail
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        detailPage == .toolDetail
                        ? DesignTokens.ColorToken.brandPrimary
                        : DesignTokens.ColorToken.textMuted
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.ColorToken.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("软件详情")

            Button {
                detailPage = .terminalWorkspace
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        detailPage == .terminalWorkspace
                        ? DesignTokens.ColorToken.brandPrimary
                        : DesignTokens.ColorToken.textMuted
                    )
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DesignTokens.ColorToken.panelBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("终端工作台")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 46)
        .background(DesignTokens.ColorToken.sidebarBackground)
    }

    private var detailPanel: some View {
        VStack(spacing: 0) {
            if !shouldHideGlobalChrome {
                detailPageTabs
            }

            Group {
                if detailPage == .terminalWorkspace {
                    CLITerminalSessionWindowView(
                        state: state,
                        onImmersiveModeChanged: { isImmersive in
                            withAnimation(.easeInOut(duration: 0.16)) {
                                isTerminalImmersiveMode = isImmersive
                            }
                        }
                    )
                } else {
                    toolDetailContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(shouldHideGlobalChrome ? Color(red: 0.08, green: 0.09, blue: 0.11) : DesignTokens.ColorToken.panelBackground)
        .onChange(of: detailPage) { _, newValue in
            if newValue != .terminalWorkspace {
                isTerminalImmersiveMode = false
            }
        }
    }

    private var toolDetailContent: some View {
        Group {
            if filteredInstallations.isEmpty {
                emptyDetailState(title: "没有匹配的软件", description: "尝试清空搜索词或切换筛选条件。")
            } else if let installation = state.installation(for: selectedToolID) {
                ToolDetailPanelView(
                    installation: installation,
                    detailProfile: installation.tool.detailProfile,
                    operationStatus: state.configOperationStatus,
                    configurationVisualization: ToolConfigurationVisualizationBuilder.build(
                        tool: installation.tool,
                        configService: state.configEditorService,
                        configPathCandidates: installation.configPaths
                    ),
                    supportsConfigEditing: installation.tool.supportsDirectConfigEditing,
                    updateCheckResult: state.updateCheckResult(for: installation.tool),
                    isCheckingUpdate: state.isCheckingUpdate(for: installation.tool),
                    isUpdating: state.isUpdating(for: installation.tool),
                    isInstalling: state.isInstalling(for: installation.tool),
                    isRepairingNpmCache: state.isRepairingNpmCache(for: installation.tool),
                    operationLogs: state.operationLog(for: installation.tool),
                    isOperationRunning: state.isCheckingUpdate(for: installation.tool)
                        || state.isUpdating(for: installation.tool)
                        || state.isInstalling(for: installation.tool)
                        || state.isRepairingNpmCache(for: installation.tool),
                    selectionSummary: selectionSummaryText,
                    canSelectPrevious: canSelectPrevious,
                    canSelectNext: canSelectNext,
                    onSelectPrevious: {
                        selectRelativeTool(offset: -1)
                    },
                    onSelectNext: {
                        selectRelativeTool(offset: 1)
                    },
                    onOpenConfig: {
                        state.openConfigEditor(for: installation.tool)
                    },
                    onOpenConfigDir: {
                        state.openConfigDirectory(for: installation.tool)
                    },
                    onOpenInstallDir: {
                        state.openInstallDirectory(for: installation.tool)
                    },
                    onRefresh: {
                        refreshAll()
                    },
                    onCheckUpdate: {
                        state.checkToolUpdate(installation.tool)
                    },
                    onInstall: {
                        state.installTool(installation.tool)
                    },
                    onInstallWithMethod: { method in
                        state.installTool(installation.tool, using: method)
                    },
                    onUpdate: {
                        state.updateTool(installation.tool)
                    },
                    onRepairNpmCache: {
                        state.repairNpmCachePermissions(for: installation.tool)
                    },
                    onUninstall: {
                        state.uninstallTool(installation.tool)
                    },
                    terminalSessions: state.terminalSessions(for: installation.tool),
                    onCreateTerminalSession: {
                        createTerminalSession(for: installation.tool)
                    },
                    onOpenTerminalWorkspace: {
                        openTerminalWorkspace()
                    },
                    onCloseLatestTerminalSession: {
                        closeLatestSession(for: installation.tool)
                    }
                )
            } else {
                emptyDetailState(title: "请选择一个软件", description: "左侧滚动列表并选中软件后，这里会展示完整详情与操作按钮。")
            }
        }
    }

    private var detailPageTabs: some View {
        HStack(spacing: 8) {
            ForEach(DetailPage.allCases) { page in
                Button {
                    if page == .terminalWorkspace {
                        detailPage = .terminalWorkspace
                    } else {
                        detailPage = page
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: page == .toolDetail ? "square.grid.2x2" : "terminal")
                            .font(.system(size: 11, weight: .semibold))
                        Text(page.title)
                            .font(.system(size: 11, weight: .semibold))
                        if page == .terminalWorkspace {
                            Text("\(state.terminalSessions.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.16), in: Capsule())
                        }
                    }
                    .foregroundStyle(
                        detailPage == page
                        ? DesignTokens.ColorToken.textInverse
                        : DesignTokens.ColorToken.textSecondary
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                detailPage == page
                                ? DesignTokens.ColorToken.brandPrimary
                                : DesignTokens.ColorToken.panelBackground
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                detailPage == page
                                ? DesignTokens.ColorToken.brandPrimary
                                : DesignTokens.ColorToken.borderStrong,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if detailPage == .terminalWorkspace {
                Button {
                    detailPage = .toolDetail
                } label: {
                    Label("返回详情", systemImage: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(DesignTokens.ColorToken.panelBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignTokens.ColorToken.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.ColorToken.borderDefault)
                .frame(height: 1)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            TextField("搜索软件名、命令、安装方式", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.textSecondary)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索词")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 1, y: 1)
    }

    private var statusFilterBar: some View {
        HStack(spacing: 5) {
            Text("状态过滤")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            ForEach(SidebarFilter.allCases) { filter in
                Button {
                    statusFilter = filter
                } label: {
                    Text(filter.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            statusFilter == filter
                            ? DesignTokens.ColorToken.textInverse
                            : DesignTokens.ColorToken.textSecondary
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(
                                    statusFilter == filter
                                    ? DesignTokens.ColorToken.brandPrimary
                                    : DesignTokens.ColorToken.panelBackground
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(
                                    statusFilter == filter
                                    ? DesignTokens.ColorToken.brandPrimary
                                    : DesignTokens.ColorToken.borderStrong,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptySidebarState: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("没有匹配结果")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textPrimary)

            Text("请调整搜索关键词或筛选条件。")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)

            Button("清空筛选") {
                searchText = ""
                statusFilter = .all
            }
            .buttonStyle(.bordered)
            .tint(DesignTokens.ColorToken.brandPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
        )
    }

    private func emptyDetailState(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(DesignTokens.ColorToken.textPrimary)
            Text(description)
                .font(.body)
                .foregroundStyle(DesignTokens.ColorToken.textMuted)
        }
        .padding(20)
    }

    private func statCard(countText: String, label: String, countColor: Color) -> some View {
        VStack(spacing: 1) {
            Text(countText)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(countColor)

            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textMuted)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignTokens.ColorToken.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignTokens.ColorToken.borderStrong, lineWidth: 1)
        )
    }

    private func refreshAll() {
        state.refreshDetections()
        state.refreshInstallations()
        state.configOperationStatus = "检测已刷新"
        syncSelectionWithInstallations()
    }

    private func createTerminalSession(for tool: ProgrammingTool) {
        guard let sessionID = state.createTerminalSessionWithDirectorySelection(preferredTool: tool) else { return }
        state.selectTerminalSession(sessionID)
        detailPage = .terminalWorkspace
    }

    private func openTerminalWorkspace() {
        detailPage = .terminalWorkspace
    }

    private func closeLatestSession(for tool: ProgrammingTool) {
        guard let latestSession = state.terminalSessions(for: tool).first else { return }
        state.removeTerminalSession(latestSession.id)
    }

    private func syncSelectionWithInstallations() {
        let visibleInstallations = filteredInstallations

        guard !visibleInstallations.isEmpty else {
            selectedToolID = nil
            listScrollPositionID = nil
            return
        }

        if let selectedToolID, visibleInstallations.contains(where: { $0.id == selectedToolID }) {
            listScrollPositionID = selectedToolID
            return
        }

        selectTool(visibleInstallations[0].id, syncScrollPosition: true)
    }

    private func selectTool(_ toolID: ProgrammingTool, syncScrollPosition: Bool) {
        guard filteredInstallations.contains(where: { $0.id == toolID }) else {
            return
        }

        let updateSelection = {
            selectedToolID = toolID
            if syncScrollPosition {
                listScrollPositionID = toolID
            }
        }

        if accessibilityReduceMotion {
            updateSelection()
        } else {
            withAnimation(.easeInOut(duration: 0.16), updateSelection)
        }
    }

    private func selectRelativeTool(offset: Int) {
        guard let selectedVisibleIndex else { return }
        let targetIndex = selectedVisibleIndex + offset
        guard filteredInstallations.indices.contains(targetIndex) else { return }
        selectTool(filteredInstallations[targetIndex].id, syncScrollPosition: true)
    }

    private var filteredInstallations: [ToolInstallation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return state.installations.filter { installation in
            guard statusFilter.matches(installation) else { return false }
            guard !query.isEmpty else { return true }

            let searchableText = [
                installation.tool.title,
                installation.tool.rawValue,
                installation.installMethod.title,
                installation.binaryPath ?? ""
            ].joined(separator: " ")

            return searchableText.localizedStandardContains(query)
        }
    }

    private var selectedVisibleIndex: Int? {
        guard let selectedToolID else { return nil }
        return filteredInstallations.firstIndex(where: { $0.id == selectedToolID })
    }

    private var selectionSummaryText: String {
        guard let selectedVisibleIndex else {
            return "0 / \(filteredInstallations.count)"
        }
        return "\(selectedVisibleIndex + 1) / \(filteredInstallations.count)"
    }

    private var canSelectPrevious: Bool {
        guard let selectedVisibleIndex else { return false }
        return selectedVisibleIndex > 0
    }

    private var canSelectNext: Bool {
        guard let selectedVisibleIndex else { return false }
        return selectedVisibleIndex < filteredInstallations.count - 1
    }

    private var shouldHideGlobalChrome: Bool {
        detailPage == .terminalWorkspace && isTerminalImmersiveMode
    }

    private func toggleBatchMode() {
        isBatchMode.toggle()
        if !isBatchMode {
            batchSelectedTools.removeAll()
        }
    }

    private func toggleBatchSelection(_ tool: ProgrammingTool) {
        if batchSelectedTools.contains(tool) {
            batchSelectedTools.remove(tool)
        } else {
            batchSelectedTools.insert(tool)
        }
    }

    private var installedBatchSelectedCount: Int {
        batchSelectedTools.filter { tool in
            state.installations.contains(where: { $0.tool == tool && $0.isInstalled })
        }.count
    }

}
