import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct CLITerminalSessionConsoleView: View {
    let session: CLITerminalSession
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let isImmersiveMode: Bool
    let ghosttyRunner: CLIGhosttyTerminalRunner?
    @State private var isImageDropTargeted = false

    init(
        session: CLITerminalSession,
        onSendData: @escaping (Data) -> Void,
        onResize: @escaping (Int, Int) -> Void,
        isImmersiveMode: Bool,
        ghosttyRunner: CLIGhosttyTerminalRunner? = nil
    ) {
        self.session = session
        self.onSendData = onSendData
        self.onResize = onResize
        self.isImmersiveMode = isImmersiveMode
        self.ghosttyRunner = ghosttyRunner
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TerminalEmulatorView(
                session: session,
                ghosttyRunner: ghosttyRunner,
                onSendData: onSendData,
                onResize: onResize
            )
            .frame(minHeight: isImmersiveMode ? 0 : 260, maxHeight: .infinity)
            .overlay {
                if isImageDropTargeted {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignTokens.ColorToken.statusInfo.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    DesignTokens.ColorToken.statusInfo.opacity(0.7),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                                )
                        )
                        .overlay {
                            Text("释放图片后将自动把路径写入终端输入")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DesignTokens.ColorToken.statusInfo)
                        }
                }
            }
            .overlay {
                if !isImmersiveMode {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.ColorToken.terminalDivider, lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: isImmersiveMode ? 0 : 8, style: .continuous))
            .onDrop(of: droppedImageContentTypes, isTargeted: $isImageDropTargeted) { providers in
                handleImageDrop(providers)
            }
        }
        .padding(isImmersiveMode ? 0 : 10)
        .background {
            RoundedRectangle(cornerRadius: isImmersiveMode ? 0 : 10, style: .continuous)
                .fill(DesignTokens.ColorToken.terminalSurface)
        }
        .overlay {
            if !isImmersiveMode {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DesignTokens.ColorToken.terminalDivider, lineWidth: 1)
            }
        }
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        if let fileProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            fileProvider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = parseDroppedFileURL(item), isDroppedImageFileURL(url) else { return }
                DispatchQueue.main.async {
                    sendImagePathToTerminal(url)
                }
            }
            return true
        }

        if let imageProvider = providers.first(where: supportsInMemoryImageDrop) {
            persistDroppedImageFromProvider(imageProvider)
            return true
        }

        return false
    }

    private var droppedImageContentTypes: [UTType] {
        [
            .fileURL,
            .png,
            .jpeg,
            .tiff,
            .image
        ]
    }

    private func supportsInMemoryImageDrop(_ provider: NSItemProvider) -> Bool {
        provider.hasItemConformingToTypeIdentifier(UTType.png.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.tiff.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
    }

    private func persistDroppedImageFromProvider(_ provider: NSItemProvider) {
        let preferredTypes: [(UTType, String)] = [
            (.png, "png"),
            (.jpeg, "jpg"),
            (.tiff, "tiff"),
            (.image, "png")
        ]

        if let selected = preferredTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0.0.identifier) }) {
            provider.loadDataRepresentation(forTypeIdentifier: selected.0.identifier) { data, _ in
                guard let data,
                      let url = Self.storeDroppedImageData(data, preferredExtension: selected.1) else { return }
                DispatchQueue.main.async {
                    sendImagePathToTerminal(url)
                }
            }
            return
        }

        provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage,
                  let pngData = Self.pngData(from: image),
                  let url = Self.storeDroppedImageData(pngData, preferredExtension: "png") else { return }
            DispatchQueue.main.async {
                sendImagePathToTerminal(url)
            }
        }
    }

    private nonisolated static func storeDroppedImageData(_ data: Data, preferredExtension: String) -> URL? {
        guard !data.isEmpty else { return nil }

        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AgentOSDroppedImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var outputData = data
        var fileExtension = preferredExtension.lowercased()
        if fileExtension != "png", let image = NSImage(data: data), let converted = Self.pngData(from: image) {
            outputData = converted
            fileExtension = "png"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "drop-\(timestamp)-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let outputURL = directory.appendingPathComponent(filename)
        do {
            try outputData.write(to: outputURL, options: .atomic)
            return outputURL
        } catch {
            return nil
        }
    }

    private nonisolated static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func sendImagePathToTerminal(_ url: URL) {
        let path = url.path
        guard !path.isEmpty else { return }
        let snippet = imageSnippetForCurrentTool(path)
        onSendData(Data((snippet + " ").utf8))
    }

    private func imageSnippetForCurrentTool(_ path: String) -> String {
        let escapedSingleQuote = path.replacingOccurrences(of: "'", with: "'\\''")
        let shellQuotedPath = "'\(escapedSingleQuote)'"

        switch session.tool {
        case .codex, .qwenCode:
            return "@\(path)"
        case .claudeCode:
            return "请分析这张图片：\(path)"
        default:
            return shellQuotedPath
        }
    }
}

private func parseDroppedFileURL(_ item: NSSecureCoding?) -> URL? {
    if let url = item as? URL {
        return url
    }
    if let data = item as? Data {
        return URL(dataRepresentation: data, relativeTo: nil)
    }
    if let text = item as? String {
        return URL(string: text)
    }
    return nil
}

private func isDroppedImageFileURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let ext = url.pathExtension.lowercased()
    guard !ext.isEmpty else { return false }
    return UTType(filenameExtension: ext)?.conforms(to: .image) == true
}

/// Ghostty Metal-rendered terminal emulator view.
private struct TerminalEmulatorView: View {
    let session: CLITerminalSession
    let ghosttyRunner: CLIGhosttyTerminalRunner?
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void

    var body: some View {
        if let ghosttyRunner {
            GhosttyTerminalEmulatorView(
                sessionID: session.id,
                runner: ghosttyRunner,
                isRunning: session.isRunning,
                onSendData: onSendData,
                onResize: onResize
            )
            // Keep Ghostty host view identity scoped to session.
            // Without this, SwiftUI may reuse one NSView across tabs and keep
            // rendering the previous session's surface.
            .id(session.id)
        } else {
            fallbackContent
        }
    }

    @ViewBuilder
    private var fallbackContent: some View {
        switch TerminalConsoleFallbackResolver.resolve(session: session, hasRunner: false) {
        case .liveSurface:
            terminalLaunchingPlaceholder
        case .launching:
            terminalLaunchingPlaceholder
        case .transcript(let text):
            terminalTranscriptPlaceholder(text: text)
        case .unavailable:
            terminalUnavailablePlaceholder
        }
    }

    private var terminalLaunchingPlaceholder: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(DesignTokens.ColorToken.terminalAccent)

            Text("终端启动中…")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)

            if !session.outputPreview.isEmpty {
                Text(session.outputPreview)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.ColorToken.terminalCanvas)
    }

    private func terminalTranscriptPlaceholder(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextPrimary)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(12)
                .textSelection(.enabled)
        }
        .background(DesignTokens.ColorToken.terminalCanvas)
    }

    private var terminalUnavailablePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
            Text("会话已结束")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)
            Text("暂无可回看输出，可直接重启该会话。")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.ColorToken.terminalCanvas)
    }
}

private enum TerminalSplitLayout: String, CaseIterable, Identifiable {
    case single
    case vertical
    case horizontal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single:
            return "单栏"
        case .vertical:
            return "左右分屏"
        case .horizontal:
            return "上下分屏"
        }
    }

    var icon: String {
        switch self {
        case .single:
            return "rectangle"
        case .vertical:
            return "rectangle.split.2x1"
        case .horizontal:
            return "rectangle.split.1x2"
        }
    }
}

private enum TerminalPaneRole {
    case primary
    case secondary

    var title: String {
        switch self {
        case .primary:
            return "主会话"
        case .secondary:
            return "副会话"
        }
    }

    var icon: String {
        switch self {
        case .primary:
            return "star.fill"
        case .secondary:
            return "square.split.2x1"
        }
    }
}

struct CLITerminalSessionWindowView: View {
    @Bindable var state: AppState
    var onImmersiveModeChanged: (Bool) -> Void = { _ in }

    @State private var activeSessionID: UUID?
    @State private var secondarySessionID: UUID?
    @State private var isImmersiveMode = false
    @State private var splitLayout: TerminalSplitLayout = .single
    @State private var focusedPane: TerminalPaneRole = .primary
    @State private var draggingSessionID: UUID?
    @State private var renamingSessionID: UUID?
    @State private var renameDraft = ""
    @State private var quickLaunchCommandDraft = ""
    @State private var isQuickLaunchPopoverPresented = false
    @State private var showsDirectorySidebar = false
    @State private var directorySidebarWidth: CGFloat = 280
    @State private var directorySidebarDragStartWidth: CGFloat?
    @FocusState private var isRenameFieldFocused: Bool
    @FocusState private var isQuickLaunchFieldFocused: Bool

    private let terminalTabDragType = UTType.text.identifier

    private enum TopBarControlTone {
        case neutral
        case accent
        case warning
        case danger
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            terminalContentArea
        }
        .onAppear {
            syncActiveSession()
            syncSecondarySession()
            onImmersiveModeChanged(isImmersiveMode)
        }
        .onChange(of: state.selectedTerminalSessionID) { _, _ in
            syncActiveSession()
            syncSecondarySession()
        }
        .onChange(of: terminalSessions.map(\.id)) { _, _ in
            syncActiveSession()
            syncSecondarySession()
        }
        .onChange(of: activeSessionID) { _, _ in
            syncSecondarySession()
        }
        .onChange(of: splitLayout) { _, newValue in
            if newValue != .single {
                isImmersiveMode = false
            }
            if newValue == .single {
                focusedPane = .primary
            }
            syncSecondarySession()
        }
        .onChange(of: isImmersiveMode) { _, newValue in
            if newValue {
                splitLayout = .single
            }
            onImmersiveModeChanged(newValue)
        }
        .onExitCommand {
            guard isImmersiveMode else { return }
            isImmersiveMode = false
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignTokens.ColorToken.terminalCanvas)
        .overlay(alignment: .topLeading) {
            splitPaneKeyboardShortcutsLayer
        }
        .sheet(isPresented: isRenameSheetPresentedBinding) {
            renameSessionSheet
        }
    }

    private var terminalSessions: [CLITerminalSession] {
        state.orderedTerminalSessions()
    }

    private var favoriteDirectoriesForMenu: [String] {
        Array(state.favoriteWorkspaceDirectories.prefix(8))
    }

    private var recentDirectoriesForMenu: [String] {
        let favoriteSet = Set(favoriteDirectoriesForMenu)
        let recent = state.recentWorkspaceDirectories.filter { !favoriteSet.contains($0) }
        return Array(recent.prefix(8))
    }

    private var closedSessionsForMenu: [ClosedTerminalSessionRecord] {
        Array(state.recentlyClosedTerminalSessions.prefix(8))
    }

    private var activeSession: CLITerminalSession? {
        if let activeSessionID,
           let session = terminalSessions.first(where: { $0.id == activeSessionID }) {
            return session
        }
        if let selectedID = state.selectedTerminalSessionID,
           let session = terminalSessions.first(where: { $0.id == selectedID }) {
            return session
        }
        return terminalSessions.last
    }

    private var secondarySession: CLITerminalSession? {
        guard splitLayout != .single else { return nil }
        guard let activeSessionID = activeSession?.id else { return nil }

        if let secondarySessionID,
           secondarySessionID != activeSessionID,
           let session = terminalSessions.first(where: { $0.id == secondarySessionID }) {
            return session
        }
        return nil
    }

    private var secondaryCandidateSessions: [CLITerminalSession] {
        guard let activeSessionID = activeSession?.id else { return [] }
        return terminalSessions.filter { $0.id != activeSessionID }
    }

    private var activeApprovalRequest: TerminalApprovalRequest? {
        guard let activeSession else { return nil }
        return state.pendingApprovalRequest(for: activeSession.id)
    }

    private var activeSessionRequiresApproval: Bool {
        guard let activeSession else { return false }
        return state.terminalRuntimeState(for: activeSession.id) == .waitingApproval
    }

    private var preferredToolForNewSession: ProgrammingTool? {
        activeSession?.tool
            ?? state.installations.first(where: { $0.isInstalled && $0.tool.supportsIntegratedTerminal })?.tool
    }

    @ViewBuilder
    private var terminalContentArea: some View {
        if let activeSession {
            HStack(spacing: 0) {
                if showsDirectorySidebar {
                    TerminalDirectorySidebarView(rootPath: activeSession.workingDirectory)
                        .frame(width: directorySidebarWidth)
                        .background(DesignTokens.ColorToken.terminalHeader)

                    directorySidebarResizer
                }

                if splitLayout == .single || secondarySession == nil {
                    terminalConsole(for: activeSession, role: .primary)
                } else if let secondarySession {
                    splitContainer(primary: activeSession, secondary: secondarySession)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            emptyTerminalState
        }
    }

    private var directorySidebarResizer: some View {
        Rectangle()
            .fill(DesignTokens.ColorToken.terminalDivider)
            .frame(width: 4)
            .overlay {
                Rectangle()
                    .fill(DesignTokens.ColorToken.terminalTextMuted.opacity(0.35))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if directorySidebarDragStartWidth == nil {
                            directorySidebarDragStartWidth = directorySidebarWidth
                        }
                        let base = directorySidebarDragStartWidth ?? directorySidebarWidth
                        directorySidebarWidth = min(max(base + value.translation.width, 200), 520)
                    }
                    .onEnded { _ in
                        directorySidebarDragStartWidth = nil
                    }
            )
    }

    private var emptyTerminalState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)

            Text("还没有终端会话")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)

            Text("请从主页面快捷操作点击“新建终端”启动。")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)

            if let preferredToolForNewSession {
                newSessionMenu(for: preferredToolForNewSession)
            } else {
                Label("暂无可用终端工具", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isRenameSheetPresentedBinding: Binding<Bool> {
        Binding(
            get: { renamingSessionID != nil },
            set: { isPresented in
                if !isPresented {
                    renamingSessionID = nil
                    renameDraft = ""
                }
            }
        )
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(terminalSessions.enumerated()), id: \.element.id) { index, session in
                        sessionTabButton(session: session, index: index + 1)
                            .onDrag {
                                draggingSessionID = session.id
                                return NSItemProvider(object: session.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [terminalTabDragType],
                                delegate: TerminalTabDropDelegate(
                                    targetSessionID: session.id,
                                    draggingSessionID: $draggingSessionID
                                ) { draggedSessionID, targetSessionID in
                                    guard let targetIndex = terminalSessions.firstIndex(where: { $0.id == targetSessionID }) else { return }
                                    state.moveTerminalSession(draggedSessionID, toIndex: targetIndex)
                                }
                            )
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                tabBarCountBadge

                if let activeSession, activeSessionRequiresApproval {
                    approvalActionBar(
                        sessionID: activeSession.id,
                        prompt: activeApprovalRequest?.prompt
                    )
                }

                if !closedSessionsForMenu.isEmpty {
                    restoreClosedSessionMenu
                }

                if !isImmersiveMode {
                    splitLayoutMenu
                }

                if activeSession != nil {
                    Button {
                        showsDirectorySidebar.toggle()
                    } label: {
                        tabBarControlLabel(
                            showsDirectorySidebar ? "隐藏目录" : "目录栏",
                            systemImage: "sidebar.left",
                            tone: .neutral
                        )
                    }
                    .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
                }

                if activeSession != nil {
                    if activeSession?.isRunning == false {
                        Button {
                            relaunchActiveSession()
                        } label: {
                            tabBarControlLabel("重新启动", systemImage: "arrow.clockwise.circle", tone: .warning)
                        }
                        .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
                    }

                    Button {
                        closeActiveSession()
                    } label: {
                        tabBarControlLabel("关闭当前", systemImage: "xmark.circle.fill", tone: .danger)
                    }
                    .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
                }

                if let activeSession {
                    Button {
                        exportSessionLog(activeSession)
                    } label: {
                        tabBarControlLabel("导出对话", systemImage: "square.and.arrow.up", tone: .accent)
                    }
                    .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
                }

                if activeSession != nil {
                    Button {
                        toggleImmersiveMode()
                    } label: {
                        tabBarControlLabel(
                            isImmersiveMode ? "退出沉浸" : "沉浸模式",
                            systemImage: isImmersiveMode
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right",
                            tone: isImmersiveMode ? .accent : .neutral
                        )
                    }
                    .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
                }

                if isImmersiveMode {
                    immersiveEscapeHintBadge
                }

                quickLaunchCommandButton

                if let preferredToolForNewSession {
                    newSessionMenu(for: preferredToolForNewSession)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tabBarControlForegroundColor(for: .neutral).opacity(0.55))
                        .frame(width: 32, height: 32)
                        .background(tabBarControlFillStyle(for: .neutral), in: Circle())
                        .overlay(
                            Circle()
                                .stroke(tabBarControlBorderColor(for: .neutral), lineWidth: 1)
                        )
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(DesignTokens.ColorToken.terminalHeader)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignTokens.ColorToken.terminalDivider)
                .frame(height: 1)
        }
    }

    private var tabBarCountBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "rectangle.stack.fill")
                .font(.system(size: 9, weight: .semibold))
            Text("会话 \(terminalSessions.count)")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tabBarControlForegroundColor(for: .neutral))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tabBarControlFillStyle(for: .neutral), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(tabBarControlBorderColor(for: .neutral), lineWidth: 1)
        )
    }

    private var immersiveEscapeHintBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "keyboard")
                .font(.system(size: 9, weight: .medium))
            Text("Esc 退出沉浸")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(DesignTokens.ColorToken.terminalElevated, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .stroke(DesignTokens.ColorToken.terminalDivider, lineWidth: 1)
        )
    }

    private func approvalActionBar(sessionID: UUID, prompt: String?) -> some View {
        HStack(spacing: 6) {
            Label(prompt ?? "检测到 CLI 授权请求", systemImage: "exclamationmark.shield")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.statusInfo)
                .lineLimit(1)
                .frame(maxWidth: 260, alignment: .leading)

            Button {
                state.approvePendingTerminalAction(sessionID)
            } label: {
                Label("允许", systemImage: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(DesignTokens.ColorToken.statusSuccess)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignTokens.ColorToken.statusSuccess.opacity(0.14))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DesignTokens.ColorToken.statusSuccess.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(.rect)

            Button {
                state.rejectPendingTerminalAction(sessionID)
            } label: {
                Label("拒绝", systemImage: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(DesignTokens.ColorToken.statusDanger)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignTokens.ColorToken.statusDanger.opacity(0.14))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DesignTokens.ColorToken.statusDanger.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(.rect)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.ColorToken.statusInfo.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DesignTokens.ColorToken.statusInfo.opacity(0.38), lineWidth: 1)
        )
    }

    private func tabBarControlLabel(
        _ title: String,
        systemImage: String,
        tone: TopBarControlTone = .neutral
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tabBarControlForegroundColor(for: tone))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tabBarControlFillStyle(for: tone), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tabBarControlBorderColor(for: tone), lineWidth: 1)
            )
    }

    private func tabBarControlForegroundColor(for tone: TopBarControlTone) -> Color {
        switch tone {
        case .neutral:
            return DesignTokens.ColorToken.terminalTextSecondary
        case .accent:
            return DesignTokens.ColorToken.terminalTextPrimary
        case .warning:
            return DesignTokens.ColorToken.statusWarning
        case .danger:
            return DesignTokens.ColorToken.terminalDanger
        }
    }

    private func tabBarControlFillStyle(for tone: TopBarControlTone) -> AnyShapeStyle {
        switch tone {
        case .danger:
            return AnyShapeStyle(DesignTokens.ColorToken.terminalDanger.opacity(0.14))
        case .warning:
            return AnyShapeStyle(DesignTokens.ColorToken.statusWarning.opacity(0.12))
        case .accent:
            return AnyShapeStyle(DesignTokens.ColorToken.terminalAccent.opacity(0.22))
        case .neutral:
            return AnyShapeStyle(DesignTokens.ColorToken.terminalElevated)
        }
    }

    private func tabBarControlBorderColor(for tone: TopBarControlTone) -> Color {
        switch tone {
        case .danger:
            return DesignTokens.ColorToken.terminalDanger.opacity(0.42)
        case .accent:
            return DesignTokens.ColorToken.terminalAccent.opacity(0.45)
        default:
            return DesignTokens.ColorToken.terminalDivider
        }
    }

    private var quickLaunchCommandButton: some View {
        Button {
            presentQuickLaunchPopover()
        } label: {
            tabBarControlLabel("快速启动CLI", systemImage: "bolt.horizontal.circle", tone: .accent)
        }
        .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
        .popover(isPresented: $isQuickLaunchPopoverPresented, arrowEdge: .top) {
            quickLaunchPopover
        }
    }

    private var quickLaunchPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快速启动编程 CLI")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextPrimary)

            Text("只需输入一行命令，例如：`codex`、`claude --continue`、`aider --model sonnet`")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
                .fixedSize(horizontal: false, vertical: true)

            TextField("输入启动命令", text: $quickLaunchCommandDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isQuickLaunchFieldFocused)
                .onSubmit {
                    launchQuickCommand()
                }

            if !state.recentQuickLaunchCommands.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近命令")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)

                    ForEach(state.recentQuickLaunchCommands, id: \.self) { command in
                        Button {
                            launchQuickCommand(command)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(command)
                                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(DesignTokens.ColorToken.terminalElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(DesignTokens.ColorToken.terminalDivider, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("取消") {
                    isQuickLaunchPopoverPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorToken.terminalTextSecondary)

                Spacer(minLength: 0)

                Button("启动") {
                    launchQuickCommand()
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorToken.terminalTextPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(DesignTokens.ColorToken.terminalAccent.opacity(0.9), in: Capsule(style: .continuous))
                .disabled(quickLaunchCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(DesignTokens.ColorToken.terminalSurface)
        .onAppear {
            if quickLaunchCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let defaultCommand = activeSession?.tool.candidates.first ?? preferredToolForNewSession?.candidates.first {
                quickLaunchCommandDraft = defaultCommand
            }
            DispatchQueue.main.async {
                isQuickLaunchFieldFocused = true
            }
        }
    }

    private var splitLayoutMenu: some View {
        Menu {
            ForEach(TerminalSplitLayout.allCases) { layout in
                Button {
                    splitLayout = layout
                } label: {
                    Label(
                        layout.title,
                        systemImage: splitLayout == layout ? "checkmark.circle.fill" : layout.icon
                    )
                }
                .disabled(layout != .single && terminalSessions.count < 2)
            }

            if splitLayout != .single, !secondaryCandidateSessions.isEmpty {
                Divider()
                Section("副会话") {
                    ForEach(secondaryCandidateSessions, id: \.id) { session in
                        Button {
                            secondarySessionID = session.id
                        } label: {
                            let isSelected = secondarySessionID == session.id
                            Label(
                                "\(session.tool.title) · \(displayPath(session.workingDirectory))",
                                systemImage: isSelected ? "checkmark" : "circle"
                            )
                        }
                    }
                }
            }
        } label: {
            tabBarControlLabel("分屏", systemImage: splitLayout.icon, tone: .neutral)
        }
        .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
    }

    private var restoreClosedSessionMenu: some View {
        Menu {
            Button("恢复最近关闭会话") {
                reopenLastClosedSession()
            }
            Divider()

            ForEach(closedSessionsForMenu) { record in
                Button(closedSessionLabel(record)) {
                    reopenClosedSession(record.id)
                }
            }

            Divider()
            Button("清空关闭记录") {
                state.clearRecentlyClosedTerminalSessions()
            }
        } label: {
            tabBarControlLabel("恢复关闭", systemImage: "arrow.uturn.backward.circle", tone: .neutral)
        }
        .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
    }

    private func splitContainer(primary: CLITerminalSession, secondary: CLITerminalSession) -> some View {
        Group {
            if splitLayout == .horizontal {
                VSplitView {
                    terminalConsole(for: primary, role: .primary)
                        .frame(minHeight: 180)
                    terminalConsole(for: secondary, role: .secondary)
                        .frame(minHeight: 180)
                }
            } else {
                HSplitView {
                    terminalConsole(for: primary, role: .primary)
                        .frame(minWidth: 240)
                    terminalConsole(for: secondary, role: .secondary)
                        .frame(minWidth: 240)
                }
            }
        }
        .background(DesignTokens.ColorToken.terminalCanvas)
    }

    private func terminalConsole(
        for session: CLITerminalSession,
        role: TerminalPaneRole
    ) -> some View {
        return VStack(spacing: 0) {
            CLITerminalSessionConsoleView(
                session: session,
                onSendData: { data in
                    state.sendTerminalData(data, to: session.id)
                },
                onResize: { cols, rows in
                    state.resizeTerminalSession(session.id, cols: cols, rows: rows)
                },
                isImmersiveMode: isImmersiveMode,
                ghosttyRunner: state.ghosttyRunner(for: session.id)
            )
        }
        .background(DesignTokens.ColorToken.terminalCanvas)
        .clipShape(RoundedRectangle(cornerRadius: splitLayout == .single ? 0 : 8, style: .continuous))
        .overlay {
            if splitLayout != .single {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        focusedPane == role
                            ? DesignTokens.ColorToken.brandPrimary.opacity(0.35)
                            : Color.clear,
                        lineWidth: 1.5
                    )
                    .animation(.easeInOut(duration: 0.12), value: focusedPane == role)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { _ in
            focusedPane = role
        })
    }

    private func sessionTabButton(session: CLITerminalSession, index: Int) -> some View {
        let isActive = session.id == activeSession?.id
        let runtimeState = state.runtimeState(for: session)
        let runtimeSource = state.runtimeStateSource(for: session.id)
        return HStack(spacing: 4) {
            Button {
                activeSessionID = session.id
                state.selectTerminalSession(session.id)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tabIndicatorColor(for: runtimeState))
                        .frame(width: 7, height: 7)
                        .overlay(alignment: .bottomTrailing) {
                            if let runtimeSource {
                                Circle()
                                    .fill(tabSourceColor(for: runtimeSource))
                                    .frame(width: 4, height: 4)
                            }
                        }

                    Text("\(session.tool.title) #\(index)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)

                    Text(runtimeStateBadgeLabel(for: runtimeState, source: runtimeSource))
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tabStatusBadgeFill(for: runtimeState), in: Capsule())
                        .foregroundStyle(tabStatusBadgeForeground(for: runtimeState))
                }
                .foregroundStyle(
                    isActive
                        ? DesignTokens.ColorToken.terminalTextPrimary
                        : DesignTokens.ColorToken.terminalTextSecondary
                )
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 7)
            }
            .buttonStyle(.plain)

            Button {
                closeSession(session.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
                    .padding(.trailing, 8)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .background(
            Capsule()
                .fill(
                    tabBackgroundColor(for: runtimeState, isActive: isActive)
                )
        )
        .overlay(
            Capsule()
                .stroke(
                    tabBorderColor(for: runtimeState, isActive: isActive),
                    lineWidth: 1
                )
        )
        .contextMenu {
            Button("重命名会话…") {
                startRenameSession(session)
            }

            Button("复制会话（同目录）") {
                duplicateSession(session)
            }

            if splitLayout != .single, session.id != activeSession?.id {
                Button("设为副会话") {
                    secondarySessionID = session.id
                }
            }

            Divider()

            Button("关闭该会话", role: .destructive) {
                closeSession(session.id)
            }

            if terminalSessions.count > 1 {
                Button("关闭其它会话") {
                    closeOtherSessions(keeping: session.id)
                }
            }
        }
    }

    private func tabIndicatorColor(for runtimeState: TerminalSessionRuntimeState) -> Color {
        switch runtimeState {
        case .syncing:
            return DesignTokens.ColorToken.terminalTextMuted
        case .working:
            return DesignTokens.ColorToken.terminalAccent
        case .waitingUserInput:
            return DesignTokens.ColorToken.statusWarning
        case .waitingApproval:
            return DesignTokens.ColorToken.statusInfo
        case .unknown:
            return DesignTokens.ColorToken.statusWarning.opacity(0.9)
        case .completedSuccess:
            return DesignTokens.ColorToken.statusSuccess
        case .completedFailure:
            return DesignTokens.ColorToken.statusDanger
        case .restoredStopped, .stopped:
            return DesignTokens.ColorToken.terminalTextMuted.opacity(0.6)
        }
    }

    private func tabSourceColor(for source: TerminalRuntimeSignalSource) -> Color {
        switch source {
        case .protocolEvent:
            return DesignTokens.ColorToken.statusInfo
        case .wrapperIPC:
            return DesignTokens.ColorToken.terminalAccent
        case .runtimeHint:
            return DesignTokens.ColorToken.statusWarning
        case .heuristicOutput:
            return DesignTokens.ColorToken.terminalTextMuted
        case .lifecycle:
            return DesignTokens.ColorToken.terminalTextSecondary
        case .fallback:
            return DesignTokens.ColorToken.terminalDivider
        }
    }

    private func runtimeStateBadgeLabel(
        for runtimeState: TerminalSessionRuntimeState,
        source: TerminalRuntimeSignalSource?
    ) -> String {
        if runtimeState == .unknown, let source {
            return "\(runtimeState.tabLabel)-\(source.shortLabel)"
        }
        return runtimeState.tabLabel
    }

    private func tabStatusBadgeFill(for runtimeState: TerminalSessionRuntimeState) -> Color {
        switch runtimeState {
        case .syncing:
            return DesignTokens.ColorToken.terminalDivider.opacity(0.4)
        case .working:
            return DesignTokens.ColorToken.terminalAccent.opacity(0.18)
        case .waitingUserInput:
            return DesignTokens.ColorToken.statusWarning.opacity(0.2)
        case .waitingApproval:
            return DesignTokens.ColorToken.statusInfo.opacity(0.2)
        case .unknown:
            return DesignTokens.ColorToken.statusWarning.opacity(0.16)
        case .completedSuccess:
            return DesignTokens.ColorToken.statusSuccess.opacity(0.22)
        case .completedFailure:
            return DesignTokens.ColorToken.statusDanger.opacity(0.2)
        case .restoredStopped, .stopped:
            return DesignTokens.ColorToken.terminalElevated
        }
    }

    private func tabStatusBadgeForeground(for runtimeState: TerminalSessionRuntimeState) -> Color {
        switch runtimeState {
        case .syncing:
            return DesignTokens.ColorToken.terminalTextMuted
        case .working:
            return DesignTokens.ColorToken.terminalAccent
        case .waitingUserInput:
            return DesignTokens.ColorToken.statusWarning
        case .waitingApproval:
            return DesignTokens.ColorToken.statusInfo
        case .unknown:
            return DesignTokens.ColorToken.statusWarning
        case .completedSuccess:
            return DesignTokens.ColorToken.statusSuccess
        case .completedFailure:
            return DesignTokens.ColorToken.statusDanger
        case .restoredStopped, .stopped:
            return DesignTokens.ColorToken.terminalTextMuted
        }
    }

    private func tabBackgroundColor(
        for runtimeState: TerminalSessionRuntimeState,
        isActive: Bool
    ) -> Color {
        switch runtimeState {
        case .completedSuccess:
            return DesignTokens.ColorToken.statusSuccess.opacity(isActive ? 0.22 : 0.14)
        case .unknown:
            return DesignTokens.ColorToken.statusWarning.opacity(isActive ? 0.14 : 0.08)
        default:
            return isActive
                ? DesignTokens.ColorToken.terminalElevated
                : DesignTokens.ColorToken.terminalHeader
        }
    }

    private func tabBorderColor(
        for runtimeState: TerminalSessionRuntimeState,
        isActive: Bool
    ) -> Color {
        switch runtimeState {
        case .completedSuccess:
            return DesignTokens.ColorToken.statusSuccess.opacity(isActive ? 0.7 : 0.46)
        case .completedFailure:
            return DesignTokens.ColorToken.statusDanger.opacity(isActive ? 0.55 : 0.38)
        case .unknown:
            return DesignTokens.ColorToken.statusWarning.opacity(isActive ? 0.62 : 0.38)
        default:
            return isActive
                ? DesignTokens.ColorToken.terminalAccent.opacity(0.45)
                : DesignTokens.ColorToken.terminalDivider
        }
    }

    private func newSessionMenu(for tool: ProgrammingTool) -> some View {
        Menu {
            Button("浏览目录并新建…") {
                createSession(for: tool, directoryPath: nil)
            }

            quickDirectorySections { path in
                createSession(for: tool, directoryPath: path)
            }
        } label: {
            tabBarControlLabel(
                "新建终端",
                systemImage: "plus.rectangle.on.rectangle",
                tone: isImmersiveMode ? .accent : .neutral
            )
        }
        .buttonStyle(TerminalTopBarButtonStyle(isImmersive: isImmersiveMode))
        .accessibilityLabel("新建终端会话")
    }

    @ViewBuilder
    private func quickDirectorySections(action: @escaping (String) -> Void) -> some View {
        if !favoriteDirectoriesForMenu.isEmpty {
            Section("收藏目录") {
                ForEach(favoriteDirectoriesForMenu, id: \.self) { path in
                    Button(displayPath(path)) {
                        action(path)
                    }
                }
            }
        }

        if !recentDirectoriesForMenu.isEmpty {
            Section("最近目录") {
                ForEach(recentDirectoriesForMenu, id: \.self) { path in
                    Button(displayPath(path)) {
                        action(path)
                    }
                }
            }
        }
    }

    private func presentQuickLaunchPopover() {
        if quickLaunchCommandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultCommand = activeSession?.tool.candidates.first ?? preferredToolForNewSession?.candidates.first {
            quickLaunchCommandDraft = defaultCommand
        }
        isQuickLaunchPopoverPresented = true
    }

    private func launchQuickCommand() {
        launchQuickCommand(quickLaunchCommandDraft)
    }

    private func launchQuickCommand(_ commandLine: String) {
        let trimmedCommand = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else { return }

        let preferredDirectory = activeSession?.workingDirectory
            ?? (state.workspacePath.isEmpty ? nil : state.workspacePath)
        guard let sessionID = state.createTerminalSession(from: trimmedCommand, workingDirectory: preferredDirectory) else {
            return
        }
        quickLaunchCommandDraft = trimmedCommand
        isQuickLaunchPopoverPresented = false
        activeSessionID = sessionID
        state.selectTerminalSession(sessionID)
        syncSecondarySession()
    }

    private func createSession(for tool: ProgrammingTool, directoryPath: String?) {
        let sessionID: UUID?
        if let directoryPath {
            state.saveWorkspace(path: directoryPath)
            sessionID = state.createTerminalSession(for: tool, workingDirectory: directoryPath)
        } else {
            sessionID = state.createTerminalSessionWithDirectorySelection(preferredTool: tool)
        }

        guard let sessionID else { return }
        activeSessionID = sessionID
        state.selectTerminalSession(sessionID)
        syncSecondarySession()
    }

    private func relaunchActiveSession() {
        guard let activeSession else { return }
        guard let newSessionID = state.relaunchTerminalSession(activeSession.id) else { return }
        activeSessionID = newSessionID
        state.selectTerminalSession(newSessionID)
        syncSecondarySession()
    }

    private func reopenLastClosedSession() {
        guard let sessionID = state.reopenLastClosedTerminalSession() else { return }
        activeSessionID = sessionID
        state.selectTerminalSession(sessionID)
        syncSecondarySession()
    }

    private func reopenClosedSession(_ closedSessionID: UUID) {
        guard let sessionID = state.reopenRecentlyClosedTerminalSession(closedSessionID) else { return }
        activeSessionID = sessionID
        state.selectTerminalSession(sessionID)
        syncSecondarySession()
    }

    private func restartSession(_ session: CLITerminalSession, using directoryPath: String) {
        guard let newSessionID = state.restartTerminalSession(session.id, workingDirectory: directoryPath) else { return }
        activeSessionID = newSessionID
        state.selectTerminalSession(newSessionID)
        syncSecondarySession()
    }

    private func restartSessionByPickingDirectory(_ session: CLITerminalSession) {
        guard let directoryPath = state.promptWorkspaceDirectoryForNewSession(initialPath: session.workingDirectory) else { return }
        restartSession(session, using: directoryPath)
    }

    private func closeActiveSession() {
        guard let activeSession else { return }
        closeSession(activeSession.id)
    }

    private func closeSession(_ sessionID: UUID) {
        state.removeTerminalSession(sessionID)
        if secondarySessionID == sessionID {
            secondarySessionID = nil
        }
        syncActiveSession()
        syncSecondarySession()
    }

    private func closeOtherSessions(keeping sessionID: UUID) {
        let otherIDs = terminalSessions.map(\.id).filter { $0 != sessionID }
        for id in otherIDs {
            state.removeTerminalSession(id)
        }
        activeSessionID = sessionID
        state.selectTerminalSession(sessionID)
        syncSecondarySession()
    }

    private func startRenameSession(_ session: CLITerminalSession) {
        renamingSessionID = session.id
        renameDraft = session.title
        DispatchQueue.main.async {
            isRenameFieldFocused = true
        }
    }

    private func applySessionRename() {
        guard let renamingSessionID else { return }
        state.renameTerminalSession(renamingSessionID, title: renameDraft)
        self.renamingSessionID = nil
        self.renameDraft = ""
    }

    private func duplicateSession(_ session: CLITerminalSession) {
        guard let duplicatedID = state.duplicateTerminalSession(session.id) else { return }
        activeSessionID = duplicatedID
        state.selectTerminalSession(duplicatedID)
        syncSecondarySession()
    }

    private func toggleImmersiveMode() {
        if !isImmersiveMode && splitLayout != .single {
            splitLayout = .single
        }
        isImmersiveMode.toggle()
    }

    private func syncActiveSession() {
        if let activeSessionID, terminalSessions.contains(where: { $0.id == activeSessionID }) {
            return
        }
        if let selectedSessionID = state.selectedTerminalSessionID,
           terminalSessions.contains(where: { $0.id == selectedSessionID }) {
            activeSessionID = selectedSessionID
            return
        }
        activeSessionID = terminalSessions.last?.id
        if activeSessionID == nil {
            isImmersiveMode = false
            splitLayout = .single
        }
    }

    private func syncSecondarySession() {
        guard splitLayout != .single else {
            secondarySessionID = nil
            return
        }

        guard let activeSessionID = activeSession?.id else {
            secondarySessionID = nil
            splitLayout = .single
            return
        }

        let candidates = terminalSessions.filter { $0.id != activeSessionID }
        guard !candidates.isEmpty else {
            secondarySessionID = nil
            splitLayout = .single
            return
        }

        if let secondarySessionID, candidates.contains(where: { $0.id == secondarySessionID }) {
            return
        }
        secondarySessionID = candidates.last?.id
    }

    // MARK: - Split Pane Keyboard Shortcuts

    /// Hidden zero-size button group that registers keyboard shortcuts for split-pane operations.
    /// SwiftUI processes `.keyboardShortcut()` via `performKeyEquivalent`, which runs before
    /// `NSView.keyDown`, so these shortcuts work even when the terminal NSView has first responder.
    private var splitPaneKeyboardShortcutsLayer: some View {
        Group {
            // Cmd+D: 左右分屏
            Button("") {
                guard terminalSessions.count >= 2 else { return }
                guard !isImmersiveMode else { return }
                splitLayout = .vertical
                focusedPane = .primary
                syncSecondarySession()
            }
            .keyboardShortcut("d", modifiers: [.command])

            // Cmd+Shift+D: 上下分屏
            Button("") {
                guard terminalSessions.count >= 2 else { return }
                guard !isImmersiveMode else { return }
                splitLayout = .horizontal
                focusedPane = .primary
                syncSecondarySession()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            // Cmd+]: 焦点切换至下一面板
            Button("") { focusNextPane() }
                .keyboardShortcut("]", modifiers: [.command])

            // Cmd+[: 焦点切换至上一面板
            Button("") { focusPreviousPane() }
                .keyboardShortcut("[", modifiers: [.command])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func focusNextPane() {
        guard splitLayout != .single else { return }
        guard let primaryID = activeSession?.id,
              let secondaryID = secondarySession?.id else { return }
        activeSessionID = secondaryID
        secondarySessionID = primaryID
        state.selectTerminalSession(secondaryID)
        focusedPane = .primary
    }

    private func focusPreviousPane() {
        focusNextPane()
    }

    private func displayPath(_ path: String) -> String {
        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return path.replacingOccurrences(of: homePath, with: "~")
        }
        return path
    }

    private func exportSessionLog(_ session: CLITerminalSession) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = defaultTranscriptFilename(for: session)
        panel.prompt = "导出对话"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            state.configOperationStatus = "已取消导出。"
            return
        }

        state.exportTerminalSessionTranscript(session.id, to: destinationURL)
    }

    private func defaultTranscriptFilename(for session: CLITerminalSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let slug = session.tool.rawValue.replacingOccurrences(of: " ", with: "-")
        return "\(slug)-\(timestamp).conversation.md"
    }

    private func closedSessionLabel(_ record: ClosedTerminalSessionRecord) -> String {
        "\(record.tool.title) · \(displayPath(record.workingDirectory))"
    }

    private var renameSessionSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名会话")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignTokens.ColorToken.textPrimary)

            TextField("输入会话名称", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isRenameFieldFocused)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                Button("取消") {
                    renamingSessionID = nil
                    renameDraft = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("保存") {
                    applySessionRename()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}

private struct TerminalDirectorySidebarView: View {
    let rootPath: String

    @State private var directoryNodes: [TerminalDirectoryNode] = []
    @State private var isLoading = false
    @State private var loadingErrorMessage: String?
    @State private var didHitNodeLimit = false
    @State private var refreshToken = UUID()
    @State private var latestLoadToken = UUID()
    @State private var searchQuery = ""
    @State private var showsCodeFilesOnly = false
    @State private var expandedDirectoryPaths: Set<String> = []
    @State private var previousRootPath = ""

    private let maxDepth = 6
    private let maxNodeCount = 3_000

    private var normalizedRootPath: String {
        let expanded = NSString(string: rootPath).expandingTildeInPath
        if expanded.isEmpty {
            return NSHomeDirectory()
        }
        return expanded
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleNodes: [TerminalDirectoryNode] {
        Self.filterNodes(
            directoryNodes,
            query: trimmedSearchQuery,
            codeOnly: showsCodeFilesOnly
        )
    }

    private var summary: TerminalDirectorySummary {
        Self.summarize(nodes: directoryNodes)
    }

    private var isFiltering: Bool {
        !trimmedSearchQuery.isEmpty || showsCodeFilesOnly
    }

    // Match terminal panel tones to avoid sidebar/terminal color split.
    private let sidebarBaseColor = DesignTokens.ColorToken.terminalHeader
    private let sidebarElevatedColor = DesignTokens.ColorToken.terminalElevated
    private let sidebarBorderColor = DesignTokens.ColorToken.terminalDivider
    private let sidebarTextPrimary = DesignTokens.ColorToken.terminalTextPrimary
    private let sidebarTextSecondary = DesignTokens.ColorToken.terminalTextSecondary
    private let sidebarTextMuted = DesignTokens.ColorToken.terminalTextMuted
    private let sidebarAccentColor = DesignTokens.ColorToken.terminalAccent
    private let sidebarWarningColor = Color(red: 0.94, green: 0.74, blue: 0.30)
    private let sidebarTagFillColor = DesignTokens.ColorToken.terminalSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Rectangle()
                .fill(sidebarBorderColor)
                .frame(height: 1)

            filterToolbar

            Rectangle()
                .fill(sidebarBorderColor)
                .frame(height: 1)

            content

            if didHitNodeLimit {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(sidebarWarningColor)
                    Text("目录内容过多，仅展示前 \(maxNodeCount) 项。")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(sidebarTextMuted)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(sidebarElevatedColor)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(sidebarBorderColor)
                        .frame(height: 1)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(sidebarBaseColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(sidebarBorderColor)
                .frame(width: 1)
        }
        .onAppear {
            reloadDirectoryTree()
        }
        .onChange(of: rootPath) { _, _ in
            reloadDirectoryTree()
        }
        .onChange(of: refreshToken) { _, _ in
            reloadDirectoryTree()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("文件目录", systemImage: "folder.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sidebarTextPrimary)

                Spacer(minLength: 0)

                Button {
                    openRootDirectoryInFinder()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sidebarTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("在 Finder 打开目录")

                Button {
                    refreshToken = UUID()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(sidebarTextSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("刷新目录")
            }

            Text(displayPath(normalizedRootPath))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(sidebarTextMuted)
                .lineLimit(1)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Text("目录 \(summary.directoryCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(sidebarTextSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sidebarTagFillColor, in: Capsule())

                Text("文件 \(summary.fileCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(sidebarTextSecondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sidebarTagFillColor, in: Capsule())

                Text("代码 \(summary.codeFileCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(sidebarAccentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sidebarAccentColor.opacity(0.16), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(sidebarAccentColor.opacity(0.4), lineWidth: 1)
                    )

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }

    private var filterToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(sidebarTextMuted)

                TextField("搜索目录 / 文件", text: $searchQuery)
                    .font(.system(size: 11, weight: .regular))
                    .textFieldStyle(.plain)
                    .disableAutocorrection(true)

                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(sidebarTextMuted)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(sidebarElevatedColor.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(sidebarBorderColor.opacity(0.9), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Button {
                    showsCodeFilesOnly.toggle()
                } label: {
                    Label("仅看代码文件", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            showsCodeFilesOnly
                            ? sidebarAccentColor
                            : sidebarTextSecondary
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            showsCodeFilesOnly
                            ? sidebarAccentColor.opacity(0.16)
                            : sidebarElevatedColor.opacity(0.75),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    showsCodeFilesOnly
                                    ? sidebarAccentColor.opacity(0.44)
                                    : sidebarBorderColor.opacity(0.9),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)

                if isFiltering {
                    Text("已过滤")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(sidebarWarningColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(sidebarWarningColor.opacity(0.16), in: Capsule())
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && directoryNodes.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在读取目录…")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(sidebarTextMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else if let loadingErrorMessage {
            VStack(spacing: 10) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(sidebarWarningColor)

                Text(loadingErrorMessage)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(sidebarTextMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Button("重新读取") {
                    refreshToken = UUID()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(sidebarAccentColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else if visibleNodes.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle" : "folder")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(sidebarTextMuted)
                Text(isFiltering ? "没有匹配结果" : "目录为空")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(sidebarTextMuted)

                if isFiltering {
                    Button("清除筛选") {
                        searchQuery = ""
                        showsCodeFilesOnly = false
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(sidebarAccentColor)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleNodes) { node in
                        TerminalDirectoryNodeView(
                            node: node,
                            depth: 0,
                            expandedDirectoryPaths: $expandedDirectoryPaths,
                            onOpen: openNode,
                            onRevealInFinder: revealNodeInFinder
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 9)
            }
            .scrollIndicators(.visible)
        }
    }

    private func reloadDirectoryTree() {
        let currentRootPath = normalizedRootPath
        let rootPathChanged = currentRootPath != previousRootPath
        if rootPathChanged {
            previousRootPath = currentRootPath
            expandedDirectoryPaths = []
            searchQuery = ""
            showsCodeFilesOnly = false
        }

        let loadToken = UUID()
        latestLoadToken = loadToken
        isLoading = true
        loadingErrorMessage = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = Self.buildDirectorySnapshot(
                rootPath: currentRootPath,
                maxDepth: maxDepth,
                maxNodeCount: maxNodeCount
            )

            DispatchQueue.main.async {
                guard latestLoadToken == loadToken else { return }
                isLoading = false
                directoryNodes = snapshot.nodes
                didHitNodeLimit = snapshot.didHitNodeLimit
                loadingErrorMessage = snapshot.errorMessage

                let allDirectoryPaths = Self.collectDirectoryPaths(in: snapshot.nodes)
                expandedDirectoryPaths = expandedDirectoryPaths.intersection(allDirectoryPaths)

                if rootPathChanged || expandedDirectoryPaths.isEmpty {
                    expandedDirectoryPaths = Self.defaultExpandedDirectoryPaths(from: snapshot.nodes)
                }
            }
        }
    }

    private func displayPath(_ path: String) -> String {
        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return path.replacingOccurrences(of: homePath, with: "~")
        }
        return path
    }

    private func openRootDirectoryInFinder() {
        revealPathInFinder(normalizedRootPath)
    }

    private func openNode(_ node: TerminalDirectoryNode) {
        let url = URL(fileURLWithPath: node.path)
        if node.isDirectory {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func revealNodeInFinder(_ node: TerminalDirectoryNode) {
        revealPathInFinder(node.path)
    }

    private func revealPathInFinder(_ path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private nonisolated static func buildDirectorySnapshot(
        rootPath: String,
        maxDepth: Int,
        maxNodeCount: Int
    ) -> TerminalDirectorySnapshot {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
            return TerminalDirectorySnapshot(
                nodes: [],
                didHitNodeLimit: false,
                errorMessage: "目录不存在：\(compactPath(rootPath))"
            )
        }
        guard isDirectory.boolValue else {
            return TerminalDirectorySnapshot(
                nodes: [],
                didHitNodeLimit: false,
                errorMessage: "当前路径不是目录：\(compactPath(rootPath))"
            )
        }

        var remaining = maxNodeCount
        var didHitLimit = false
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        let nodes = buildNodes(
            in: rootURL,
            depth: 0,
            maxDepth: maxDepth,
            remaining: &remaining,
            didHitLimit: &didHitLimit
        )

        return TerminalDirectorySnapshot(
            nodes: nodes,
            didHitNodeLimit: didHitLimit,
            errorMessage: nil
        )
    }

    private nonisolated static func buildNodes(
        in directoryURL: URL,
        depth: Int,
        maxDepth: Int,
        remaining: inout Int,
        didHitLimit: inout Bool
    ) -> [TerminalDirectoryNode] {
        guard depth <= maxDepth else { return [] }
        guard remaining > 0 else {
            didHitLimit = true
            return []
        }

        let keys: Set<URLResourceKey> = [
            .nameKey,
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]

        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        var nodes: [TerminalDirectoryNode] = []
        nodes.reserveCapacity(min(urls.count, remaining))

        for url in urls {
            if remaining <= 0 {
                didHitLimit = true
                break
            }

            guard let values = try? url.resourceValues(forKeys: keys) else {
                continue
            }

            let name = values.name ?? url.lastPathComponent
            if name.hasPrefix(".") {
                continue
            }

            let isDirectory = values.isDirectory == true
            let isPackage = values.isPackage == true
            let isSymbolicLink = values.isSymbolicLink == true

            remaining -= 1
            var children: [TerminalDirectoryNode] = []
            if isDirectory && !isPackage && !isSymbolicLink && depth < maxDepth {
                children = buildNodes(
                    in: url,
                    depth: depth + 1,
                    maxDepth: maxDepth,
                    remaining: &remaining,
                    didHitLimit: &didHitLimit
                )
            }

            nodes.append(
                TerminalDirectoryNode(
                    path: url.path,
                    name: name,
                    isDirectory: isDirectory,
                    children: children.isEmpty ? nil : children
                )
            )
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private nonisolated static func filterNodes(
        _ nodes: [TerminalDirectoryNode],
        query: String,
        codeOnly: Bool
    ) -> [TerminalDirectoryNode] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return nodes.compactMap { node in
            let filteredChildren = filterNodes(
                node.children ?? [],
                query: normalizedQuery,
                codeOnly: codeOnly
            )

            let matchesQuery = normalizedQuery.isEmpty || node.name.localizedStandardContains(normalizedQuery)
            if node.isDirectory {
                let keepForCode = !codeOnly || node.containsCodeRelatedContent
                let keepForQuery = normalizedQuery.isEmpty || matchesQuery || !filteredChildren.isEmpty
                guard keepForCode, keepForQuery else { return nil }

                return TerminalDirectoryNode(
                    path: node.path,
                    name: node.name,
                    isDirectory: true,
                    children: filteredChildren.isEmpty ? nil : filteredChildren
                )
            }

            guard !codeOnly || node.isCodeRelatedFile else { return nil }
            guard matchesQuery else { return nil }
            return node
        }
    }

    private nonisolated static func summarize(nodes: [TerminalDirectoryNode]) -> TerminalDirectorySummary {
        nodes.reduce(TerminalDirectorySummary()) { partial, node in
            var value = partial
            if node.isDirectory {
                value.directoryCount += 1
            } else {
                value.fileCount += 1
            }
            if node.isCodeRelatedFile {
                value.codeFileCount += 1
            }
            if let children = node.children {
                value = value + summarize(nodes: children)
            }
            return value
        }
    }

    private nonisolated static func collectDirectoryPaths(in nodes: [TerminalDirectoryNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes where node.isDirectory {
            paths.insert(node.path)
            if let children = node.children {
                paths.formUnion(collectDirectoryPaths(in: children))
            }
        }
        return paths
    }

    private nonisolated static func defaultExpandedDirectoryPaths(from nodes: [TerminalDirectoryNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes where node.isDirectory {
            paths.insert(node.path)
        }
        return paths
    }

    private nonisolated static func compactPath(_ path: String) -> String {
        let homePath = NSHomeDirectory()
        if path.hasPrefix(homePath) {
            return path.replacingOccurrences(of: homePath, with: "~")
        }
        return path
    }
}

private struct TerminalDirectorySummary {
    var directoryCount = 0
    var fileCount = 0
    var codeFileCount = 0

    static func + (lhs: TerminalDirectorySummary, rhs: TerminalDirectorySummary) -> TerminalDirectorySummary {
        TerminalDirectorySummary(
            directoryCount: lhs.directoryCount + rhs.directoryCount,
            fileCount: lhs.fileCount + rhs.fileCount,
            codeFileCount: lhs.codeFileCount + rhs.codeFileCount
        )
    }
}

private struct TerminalDirectorySnapshot {
    let nodes: [TerminalDirectoryNode]
    let didHitNodeLimit: Bool
    let errorMessage: String?
}

private struct TerminalDirectoryNode: Identifiable {
    let id: String
    let path: String
    let name: String
    let isDirectory: Bool
    let children: [TerminalDirectoryNode]?
    let containsCodeRelatedContent: Bool
    let isCodeRelatedFile: Bool
    let codeLanguageTag: String?

    var fileExtensionLowercased: String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }

    init(
        path: String,
        name: String,
        isDirectory: Bool,
        children: [TerminalDirectoryNode]? = nil
    ) {
        self.id = path
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.children = children

        let lowerName = name.lowercased()
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let isCodeFile = !isDirectory && Self.isCodeFile(name: lowerName, ext: ext)
        self.isCodeRelatedFile = isCodeFile
        self.codeLanguageTag = isCodeFile ? Self.codeLanguageTag(name: lowerName, ext: ext) : nil
        let childHasCode = children?.contains(where: { $0.containsCodeRelatedContent }) ?? false
        self.containsCodeRelatedContent = isCodeFile || childHasCode
    }

    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "c", "h", "hpp", "cc", "cpp",
        "rs", "go", "py", "rb", "js", "jsx", "ts", "tsx",
        "java", "kt", "kts", "php",
        "json", "yaml", "yml", "toml", "xml", "ini", "env",
        "sh", "bash", "zsh", "fish", "ps1",
        "sql", "graphql",
        "css", "scss", "sass", "less",
        "html", "htm", "vue", "svelte",
        "md", "markdown"
    ]

    private static let codeFileNames: Set<String> = [
        "makefile", "dockerfile", "cmakelists.txt",
        "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock",
        "cargo.toml", "cargo.lock", "go.mod", "go.sum",
        "podfile", "gemfile", "rakefile",
        "requirements.txt", "pipfile", "pipfile.lock",
        "build.gradle", "settings.gradle", "gradle.properties"
    ]

    private static func isCodeFile(name: String, ext: String) -> Bool {
        codeExtensions.contains(ext) || codeFileNames.contains(name)
    }

    private static func codeLanguageTag(name: String, ext: String) -> String? {
        switch ext {
        case "swift": return "Swift"
        case "ts": return "TS"
        case "tsx": return "TSX"
        case "js": return "JS"
        case "jsx": return "JSX"
        case "py": return "Python"
        case "rs": return "Rust"
        case "go": return "Go"
        case "java": return "Java"
        case "kt", "kts": return "Kotlin"
        case "rb": return "Ruby"
        case "php": return "PHP"
        case "json": return "JSON"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "xml": return "XML"
        case "sh", "bash", "zsh", "fish": return "Shell"
        case "sql": return "SQL"
        case "css", "scss", "sass", "less": return "Style"
        case "html", "htm": return "HTML"
        case "vue": return "Vue"
        case "svelte": return "Svelte"
        case "md", "markdown": return "Markdown"
        default:
            switch name {
            case "dockerfile": return "Docker"
            case "makefile": return "Make"
            case "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock": return "NPM"
            case "cargo.toml", "cargo.lock": return "Cargo"
            case "go.mod", "go.sum": return "Go Mod"
            case "podfile": return "CocoaPods"
            case "gemfile", "rakefile": return "Ruby"
            default:
                guard !ext.isEmpty else { return nil }
                return ext.uppercased()
            }
        }
    }
}

private struct TerminalDirectoryNodeView: View {
    let node: TerminalDirectoryNode
    let depth: Int
    @Binding var expandedDirectoryPaths: Set<String>
    let onOpen: (TerminalDirectoryNode) -> Void
    let onRevealInFinder: (TerminalDirectoryNode) -> Void
    @State private var isHovering = false

    private var isExpanded: Bool {
        expandedDirectoryPaths.contains(node.path)
    }

    private var indentation: CGFloat {
        CGFloat(depth) * 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                handlePrimaryAction()
            } label: {
                nodeLabel
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovering = hovering
            }

            if node.isDirectory, isExpanded, let children = node.children, !children.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(children) { child in
                        TerminalDirectoryNodeView(
                            node: child,
                            depth: depth + 1,
                            expandedDirectoryPaths: $expandedDirectoryPaths,
                            onOpen: onOpen,
                            onRevealInFinder: onRevealInFinder
                        )
                    }
                }
            }
        }
        .contextMenu {
            if node.isDirectory {
                Button(isExpanded ? "收起目录" : "展开目录") {
                    toggleDirectoryExpansion()
                }
                Button("在 Finder 中打开目录") {
                    onOpen(node)
                }
            }

            Button("在 Finder 中显示") {
                onRevealInFinder(node)
            }

            if !node.isDirectory {
                Button("打开文件") {
                    onOpen(node)
                }
            }
        }
    }

    private func handlePrimaryAction() {
        if node.isDirectory {
            toggleDirectoryExpansion()
            return
        }
        onOpen(node)
    }

    private func toggleDirectoryExpansion() {
        if isExpanded {
            expandedDirectoryPaths.remove(node.path)
        } else {
            expandedDirectoryPaths.insert(node.path)
        }
    }

    private var nodeLabel: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: indentation)

            if node.isDirectory {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }

            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 14, alignment: .center)

            Text(node.name)
                .font(.system(size: 11, weight: node.isDirectory ? .semibold : .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)

            Spacer(minLength: 0)

            if node.isDirectory {
                if node.containsCodeRelatedContent {
                    Circle()
                        .fill(DesignTokens.ColorToken.statusInfo.opacity(0.8))
                        .frame(width: 6, height: 6)
                }

                Text("\(node.children?.count ?? 0)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorToken.terminalTextMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DesignTokens.ColorToken.terminalSurface, in: Capsule())
            } else if node.isCodeRelatedFile, let tag = node.codeLanguageTag {
                Text(tag)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(codeBadgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(codeBadgeColor.opacity(0.15), in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(codeBadgeColor.opacity(0.36), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isHovering {
            return DesignTokens.ColorToken.terminalElevated
        }
        return .clear
    }

    private var textColor: Color {
        if node.isCodeRelatedFile {
            return DesignTokens.ColorToken.terminalAccent
        }
        return node.isDirectory
            ? DesignTokens.ColorToken.terminalTextPrimary
            : DesignTokens.ColorToken.terminalTextSecondary
    }

    private var iconColor: Color {
        if node.isDirectory {
            return node.containsCodeRelatedContent
                ? DesignTokens.ColorToken.terminalAccent
                : DesignTokens.ColorToken.terminalTextSecondary
        }
        return node.isCodeRelatedFile
            ? DesignTokens.ColorToken.terminalAccent
            : DesignTokens.ColorToken.terminalTextMuted
    }

    private var codeBadgeColor: Color {
        switch node.fileExtensionLowercased {
        case "swift":
            return Color(red: 1.0, green: 0.52, blue: 0.15)
        case "rs":
            return Color(red: 0.85, green: 0.46, blue: 0.24)
        case "py":
            return Color(red: 0.33, green: 0.62, blue: 0.98)
        case "ts", "tsx":
            return Color(red: 0.20, green: 0.52, blue: 0.93)
        case "js", "jsx":
            return Color(red: 0.92, green: 0.74, blue: 0.12)
        case "json", "yaml", "yml", "toml":
            return Color(red: 0.29, green: 0.72, blue: 0.46)
        default:
            return Color(red: 0.37, green: 0.75, blue: 1.0)
        }
    }

    private var iconName: String {
        if node.isDirectory {
            return "folder.fill"
        }

        switch node.fileExtensionLowercased {
        case "md", "markdown":
            return "doc.richtext"
        case "json", "yaml", "yml", "toml", "xml":
            return "curlybraces.square"
        case "sh", "bash", "zsh", "fish":
            return "terminal"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "heic":
            return "photo"
        case "swift", "m", "mm", "c", "h", "hpp", "cc", "cpp", "rs", "go", "py", "rb",
             "js", "jsx", "ts", "tsx", "java", "kt", "kts", "php", "sql", "css", "scss",
             "sass", "less", "html", "htm", "vue", "svelte":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc.text"
        }
    }
}

private struct TerminalTopBarButtonStyle: ButtonStyle {
    let isImmersive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? (isImmersive ? 0.86 : 0.92) : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct TerminalTabDropDelegate: DropDelegate {
    let targetSessionID: UUID
    @Binding var draggingSessionID: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingSessionID, draggingSessionID != targetSessionID else { return }
        onMove(draggingSessionID, targetSessionID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingSessionID = nil
        return true
    }
}
