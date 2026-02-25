import AppKit
import Foundation
import GhosttyKit

// MARK: - Runtime Bootstrap

/// `libghostty` requires one-time global initialization before any app/surface API.
private enum GhosttyRuntimeBootstrap {
    static let status: (isReady: Bool, failureReason: String?) = {
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        if result == Int32(GHOSTTY_SUCCESS) {
            return (true, nil)
        }
        return (false, "ghostty_init 失败（code=\(result)）")
    }()
}

// MARK: - GhosttyConfig

/// Swift wrapper around `ghostty_config_t`.
final class GhosttyConfig: @unchecked Sendable {
    let raw: ghostty_config_t
    let diagnostics: [String]

    init?() {
        guard let config = ghostty_config_new() else { return nil }
        self.raw = config

        // Load user/system defaults just like the official app startup flow.
        ghostty_config_load_default_files(config)
        if let runtimeConfigPath = Self.runtimeFontConfigFilePath() {
            runtimeConfigPath.withCString { ptr in
                ghostty_config_load_file(config, ptr)
            }
        }
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        let diagnosticsCount = ghostty_config_diagnostics_count(config)
        var diagnostics: [String] = []
        if diagnosticsCount > 0 {
            diagnostics.reserveCapacity(Int(diagnosticsCount))
            for index in 0..<diagnosticsCount {
                let item = ghostty_config_get_diagnostic(config, UInt32(index))
                diagnostics.append(String(cString: item.message))
            }
        }
        self.diagnostics = diagnostics
    }

    deinit {
        ghostty_config_free(raw)
    }

    private static func runtimeFontConfigFilePath() -> String? {
        let fileManager = FileManager.default
        guard var directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        directoryURL.appendPathComponent("AgentOS", isDirectory: true)
        directoryURL.appendPathComponent("GhosttyRuntime", isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            return nil
        }

        let configURL = directoryURL.appendingPathComponent("fonts.conf", isDirectory: false)
        let content = """
        # AgentOS runtime font fallback for mixed CJK/Latin rendering.
        # User config loaded later can override these values.
        font-family = "SF Mono"
        font-family = "Menlo"
        font-family = "PingFang SC"
        font-family = "Hiragino Sans GB"
        font-family = "Heiti SC"
        """

        do {
            try content.write(to: configURL, atomically: true, encoding: .utf8)
            return configURL.path
        } catch {
            return nil
        }
    }
}

// MARK: - GhosttyApp

/// Singleton wrapper for the global libghostty app instance.
final class GhosttyApp: @unchecked Sendable {
    static let shared: GhosttyApp? = {
        guard GhosttyRuntimeBootstrap.status.isReady else { return nil }
        return GhosttyApp()
    }()

    static var unavailableReason: String {
        if let reason = GhosttyRuntimeBootstrap.status.failureReason {
            return reason
        }
        return "ghostty_app_new 初始化失败（可能是 Ghostty 配置或运行时环境异常）"
    }

    let app: ghostty_app_t
    private let runtimeContext: GhosttyRuntimeContext

    private init?() {
        guard let config = GhosttyConfig() else { return nil }
        if !config.diagnostics.isEmpty {
            NSLog("Ghostty config diagnostics: \(config.diagnostics.joined(separator: " | "))")
        }

        let runtimeContext = GhosttyRuntimeContext()
        var runtimeConfig = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(runtimeContext).toOpaque(),
            supports_selection_clipboard: true,
            wakeup_cb: ghosttyRuntimeWakeupCallback,
            action_cb: ghosttyRuntimeActionCallback,
            read_clipboard_cb: ghosttyRuntimeReadClipboardCallback,
            confirm_read_clipboard_cb: ghosttyRuntimeConfirmReadClipboardCallback,
            write_clipboard_cb: ghosttyRuntimeWriteClipboardCallback,
            close_surface_cb: ghosttyRuntimeCloseSurfaceCallback
        )

        guard let app = ghostty_app_new(&runtimeConfig, config.raw) else { return nil }

        self.app = app
        self.runtimeContext = runtimeContext
        runtimeContext.app = self
    }

    func tick() {
        ghostty_app_tick(app)
    }

    deinit {
        ghostty_app_free(app)
    }
}

// MARK: - GhosttySurfaceDelegate

protocol GhosttySurfaceDelegate: AnyObject {
    func surfaceDidUpdateTitle(_ title: String)
    func surfaceDidChangeWorkingDirectory(_ path: String)
    func surfaceDidExit(code: Int32)
    func surfaceDidRenderFrame()
    func surfaceDidRequestPromptTitle(_ target: ghostty_action_prompt_title_e)
    func surfaceDidReportProgress(state: ghostty_action_progress_report_state_e, progress: Int8)
    func surfaceDidSecureInput(_ mode: ghostty_action_secure_input_e)
    func surfaceDidReadonly(_ mode: ghostty_action_readonly_e)
    func surfaceDidFinishCommand(exitCode: Int16)
}

// MARK: - GhosttySurface

/// One terminal surface backed by libghostty.
final class GhosttySurface: @unchecked Sendable {
    let surface: ghostty_surface_t
    weak var delegate: GhosttySurfaceDelegate?

    private let retainedContext: Unmanaged<GhosttySurfaceContext>

    @MainActor
    init?(
        app: GhosttyApp,
        hostView: NSView,
        command: String?,
        workingDirectory: String?,
        environment: [String: String]
    ) {
        let retainedContext = Unmanaged.passRetained(GhosttySurfaceContext())
        let contextPointer = retainedContext.toOpaque()

        var config = ghostty_surface_config_new()
        config.userdata = contextPointer
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(hostView).toOpaque())
        )
        let scale = hostView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        config.scale_factor = Double(scale)
        config.font_size = 0
        config.wait_after_command = false
        config.context = GHOSTTY_SURFACE_CONTEXT_WINDOW

        let envEntries = environment.map { ($0.key, $0.value) }
        let envKeys = envEntries.map { $0.0 }
        let envValues = envEntries.map { $0.1 }

        let maybeSurface: ghostty_surface_t? = envKeys.withCStrings { keyPointers in
            envValues.withCStrings { valuePointers in
                var envVars: [ghostty_env_var_s] = []
                envVars.reserveCapacity(envEntries.count)
                for index in 0..<envEntries.count {
                    envVars.append(
                        ghostty_env_var_s(
                            key: keyPointers[index],
                            value: valuePointers[index]
                        )
                    )
                }

                return envVars.withUnsafeMutableBufferPointer { buffer in
                    config.env_vars = buffer.baseAddress
                    config.env_var_count = envEntries.count

                    return workingDirectory.withCString { cwdPtr in
                        config.working_directory = cwdPtr
                        return command.withCString { cmdPtr in
                            config.command = cmdPtr
                            return ghostty_surface_new(app.app, &config)
                        }
                    }
                }
            }
        }

        guard let surface = maybeSurface else {
            retainedContext.release()
            return nil
        }

        self.surface = surface
        self.retainedContext = retainedContext

        let context = retainedContext.takeUnretainedValue()
        context.surface = self
        context.rawSurface = surface
    }

    func sendKeyEvent(_ event: ghostty_input_key_s) {
        _ = ghostty_surface_key(surface, event)
    }

    func translateModifiers(_ mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
        ghostty_surface_key_translation_mods(surface, mods)
    }

    func sendText(_ text: String) {
        let count = text.utf8CString.count
        guard count > 1 else { return }

        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, UInt(count - 1))
        }
    }

    /// Snapshot text from the whole surface (including scrollback when available).
    /// This is used for user-triggered transcript export without wrapping runtime
    /// commands with `/usr/bin/script`, which can degrade TUI behavior.
    func readSurfaceTextSnapshot() -> String? {
        var text = ghostty_text_s(
            tl_px_x: 0,
            tl_px_y: 0,
            offset_start: 0,
            offset_len: 0,
            text: nil,
            text_len: 0
        )

        let selection = ghostty_selection_s(
            top_left: ghostty_point_s(
                tag: GHOSTTY_POINT_SURFACE,
                coord: GHOSTTY_POINT_COORD_TOP_LEFT,
                x: 0,
                y: 0
            ),
            bottom_right: ghostty_point_s(
                tag: GHOSTTY_POINT_SURFACE,
                coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
                x: 0,
                y: 0
            ),
            rectangle: false
        )

        guard ghostty_surface_read_text(surface, selection, &text),
              let pointer = text.text,
              text.text_len > 0
        else {
            return nil
        }

        let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(text.text_len))
        let data = Data(bytes)
        ghostty_surface_free_text(surface, &text)
        return String(decoding: data, as: UTF8.self)
    }

    func sendMouseButton(
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e,
        modifiers: ghostty_input_mods_e
    ) {
        _ = ghostty_surface_mouse_button(surface, state, button, modifiers)
    }

    func sendMousePosition(x: Double, y: Double, modifiers: ghostty_input_mods_e) {
        ghostty_surface_mouse_pos(surface, x, y, modifiers)
    }

    func sendMouseScroll(x: Double, y: Double, modifiers: ghostty_input_scroll_mods_t) {
        ghostty_surface_mouse_scroll(surface, x, y, modifiers)
    }

    func resize(width: UInt32, height: UInt32) {
        ghostty_surface_set_size(surface, width, height)
    }

    func refresh() {
        ghostty_surface_refresh(surface)
    }

    func draw() {
        ghostty_surface_draw(surface)
    }

    func setContentScale(x: Double, y: Double) {
        ghostty_surface_set_content_scale(surface, x, y)
    }

    func setFocused(_ focused: Bool) {
        ghostty_surface_set_focus(surface, focused)
    }

    func requestClose() {
        ghostty_surface_request_close(surface)
    }

    func processExited() -> Bool {
        ghostty_surface_process_exited(surface)
    }

    func cursorIsAtPrompt() -> Bool {
        ghostty_surface_cursor_is_at_prompt(surface)
    }

    func semanticPromptSeen() -> Bool {
        ghostty_surface_semantic_prompt_seen(surface)
    }

    func cursorSemanticContent() -> ghostty_surface_cursor_content_e {
        ghostty_surface_cursor_semantic_content(surface)
    }

    deinit {
        ghostty_surface_free(surface)
        retainedContext.release()
    }
}

// MARK: - Runtime Callback Contexts

private final class GhosttyRuntimeContext: @unchecked Sendable {
    weak var app: GhosttyApp?
    private let lock = NSLock()
    private var tickScheduled = false

    func scheduleTickIfNeeded(_ work: @escaping () -> Void) {
        lock.lock()
        if tickScheduled {
            lock.unlock()
            return
        }
        tickScheduled = true
        lock.unlock()
        work()
    }

    func markTickCompleted() {
        lock.lock()
        tickScheduled = false
        lock.unlock()
    }
}

private final class GhosttySurfaceContext: @unchecked Sendable {
    weak var surface: GhosttySurface?
    var rawSurface: ghostty_surface_t?
    private let lock = NSLock()
    private var lastPromptDispatchTime: TimeInterval = 0
    private var lastReadonlyDispatchTime: TimeInterval = 0
    private var lastProgressDispatchTime: TimeInterval = 0
    private var lastProgressStateValue: Int32 = .min

    func shouldForwardPrompt(minimumInterval: TimeInterval = 0.10) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        lock.lock()
        defer { lock.unlock() }

        if now - lastPromptDispatchTime < minimumInterval {
            return false
        }
        lastPromptDispatchTime = now
        return true
    }

    func shouldForwardReadonly(minimumInterval: TimeInterval = 0.10) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        lock.lock()
        defer { lock.unlock() }

        if now - lastReadonlyDispatchTime < minimumInterval {
            return false
        }
        lastReadonlyDispatchTime = now
        return true
    }

    func shouldForwardProgress(
        state: ghostty_action_progress_report_state_e,
        minimumInterval: TimeInterval = 0.10
    ) -> Bool {
        let now = Date.timeIntervalSinceReferenceDate
        let stateValue = Int32(state.rawValue)

        lock.lock()
        defer { lock.unlock() }

        if stateValue == lastProgressStateValue,
           now - lastProgressDispatchTime < minimumInterval {
            return false
        }
        lastProgressStateValue = stateValue
        lastProgressDispatchTime = now
        return true
    }
}

// MARK: - Runtime C Callbacks

private func ghosttyRuntimeWakeupCallback(_ userdata: UnsafeMutableRawPointer?) {
    guard let userdata else { return }
    let context = Unmanaged<GhosttyRuntimeContext>.fromOpaque(userdata).takeUnretainedValue()
    context.scheduleTickIfNeeded {
        DispatchQueue.main.async {
            defer {
                context.markTickCompleted()
            }
            guard let app = context.app else { return }
            app.tick()
        }
    }
}

private func ghosttyRuntimeActionCallback(
    _ app: ghostty_app_t?,
    _ target: ghostty_target_s,
    _ action: ghostty_action_s
) -> Bool {
    guard target.tag == GHOSTTY_TARGET_SURFACE,
          let rawSurface = target.target.surface,
          let userdata = ghostty_surface_userdata(rawSurface)
    else {
        return false
    }

    let context = Unmanaged<GhosttySurfaceContext>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = context.surface else { return false }

    switch action.tag {
    case GHOSTTY_ACTION_SET_TITLE:
        guard let titlePtr = action.action.set_title.title else { return false }
        let title = String(cString: titlePtr)
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidUpdateTitle(title)
        }
        return true

    case GHOSTTY_ACTION_PWD:
        guard let pwdPtr = action.action.pwd.pwd else { return false }
        let path = String(cString: pwdPtr)
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidChangeWorkingDirectory(path)
        }
        return true

    case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
        let rawCode = action.action.child_exited.exit_code
        let exitCode: Int32 = rawCode > UInt32(Int32.max) ? Int32.max : Int32(rawCode)
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidExit(code: exitCode)
        }
        return true

    case GHOSTTY_ACTION_PROMPT_TITLE:
        let promptTarget = action.action.prompt_title
        guard context.shouldForwardPrompt() else { return true }
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidRequestPromptTitle(promptTarget)
        }
        return true

    case GHOSTTY_ACTION_RENDER:
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidRenderFrame()
        }
        return true

    case GHOSTTY_ACTION_SECURE_INPUT:
        let secureInputMode = action.action.secure_input
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidSecureInput(secureInputMode)
        }
        return true

    case GHOSTTY_ACTION_READONLY:
        let readonlyMode = action.action.readonly
        guard context.shouldForwardReadonly() else { return true }
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidReadonly(readonlyMode)
        }
        return true

    case GHOSTTY_ACTION_PROGRESS_REPORT:
        let progressState = action.action.progress_report.state
        guard context.shouldForwardProgress(state: progressState) else { return true }
        let progress = action.action.progress_report.progress
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidReportProgress(state: progressState, progress: progress)
        }
        return true

    case GHOSTTY_ACTION_COMMAND_FINISHED:
        let exitCode = action.action.command_finished.exit_code
        DispatchQueue.main.async {
            surface.delegate?.surfaceDidFinishCommand(exitCode: exitCode)
        }
        return true

    default:
        return false
    }
}

private func ghosttyRuntimeReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ state: UnsafeMutableRawPointer?
) {
    guard let userdata else { return }

    let context = Unmanaged<GhosttySurfaceContext>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = context.rawSurface else { return }

    let string = NSPasteboard.general.string(forType: .string) ?? ""
    string.withCString { ptr in
        ghostty_surface_complete_clipboard_request(surface, ptr, state, false)
    }
}

private func ghosttyRuntimeConfirmReadClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ string: UnsafePointer<CChar>?,
    _ state: UnsafeMutableRawPointer?,
    _ request: ghostty_clipboard_request_e
) {
    // Minimal integration: libghostty asks host to confirm a clipboard read.
    // We currently auto-confirm by returning the provided value as-is.
    guard let userdata else { return }

    let context = Unmanaged<GhosttySurfaceContext>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = context.rawSurface else { return }

    let value = string.map(String.init(cString:)) ?? ""
    value.withCString { ptr in
        ghostty_surface_complete_clipboard_request(surface, ptr, state, true)
    }
}

private func ghosttyRuntimeWriteClipboardCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ location: ghostty_clipboard_e,
    _ content: UnsafePointer<ghostty_clipboard_content_s>?,
    _ len: Int,
    _ confirm: Bool
) {
    guard len > 0, let content else { return }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    let items = UnsafeBufferPointer(start: content, count: len)
    if let textItem = items.first(where: {
        guard let mime = $0.mime else { return false }
        return String(cString: mime) == "text/plain"
    }), let value = textItem.data {
        pasteboard.setString(String(cString: value), forType: .string)
        return
    }

    if let first = items.first, let value = first.data {
        pasteboard.setString(String(cString: value), forType: .string)
    }
}

private func ghosttyRuntimeCloseSurfaceCallback(
    _ userdata: UnsafeMutableRawPointer?,
    _ processAlive: Bool
) {
    guard let userdata else { return }

    let context = Unmanaged<GhosttySurfaceContext>.fromOpaque(userdata).takeUnretainedValue()
    guard let surface = context.surface else { return }

    if processAlive {
        return
    }

    DispatchQueue.main.async {
        surface.delegate?.surfaceDidExit(code: -1)
    }
}

// MARK: - CLIGhosttyTerminalRunner

/// Terminal runner backed by libghostty only.
final class CLIGhosttyTerminalRunner: RuntimeStateHintingTerminalRunner, @unchecked Sendable {
    enum BackendKind {
        case pending
        case ghosttyMetal
        case unavailable
    }

    private enum RuntimeStateProfile {
        case generic
        case codex
    }

    var onOutput: ((Data) -> Void)?
    var onWorkingDirectoryChange: ((String?) -> Void)?
    var onExit: ((Int32) -> Void)?
    var onRuntimeStateHint: ((TerminalSessionRuntimeState) -> Void)?

    private var surface: GhosttySurface?
    private var ghosttyApp: GhosttyApp?
    private var launchRequest: GhosttyLaunchRequest?
    private weak var hostView: GhosttyTerminalSurfaceView?
    private var retainedHostView: GhosttyTerminalSurfaceView?
    private var pendingAttachWorkItem: DispatchWorkItem?
    private var activityEvaluationTimer: DispatchSourceTimer?
    private var renderActivityTimeline: [TimeInterval] = []
    private var lastLaunchAt: Date = .distantPast
    private var lastSubmittedInputAt: Date = .distantPast
    private var lastExplicitWaitingAt: Date = .distantPast
    private var lastProgressWorkingAt: Date = .distantPast
    private var semanticPromptObserved = false
    private var lastSurfaceSnapshotText: String?
    private var lastNonEmptySurfaceSnapshotText: String?
    private var lastSurfaceSnapshotSampleAt: TimeInterval = 0
    private var lastSurfaceTextChangedAt: TimeInterval = 0
    private var waitingCandidateSince: TimeInterval = 0
    private var lastPromptSignalAt: TimeInterval = 0
    private var waitingStateLockedSince: TimeInterval = 0
    private var runtimeStateProfile: RuntimeStateProfile = .generic
    private var lastRuntimeHintState: TerminalSessionRuntimeState?
    private var lastRuntimeHintAt: Date = .distantPast

    private let exitLock = NSLock()
    private var didEmitExit = false

    // We choose the SwiftUI view path based on backend selection, not whether
    // a surface is already instantiated.
    private var usesGhosttyBackend = false
    private(set) var backendKind: BackendKind = .pending
    private(set) var backendMessage: String?

    /// True when Ghostty backend is selected for this runner.
    var isMetalRendering: Bool { usesGhosttyBackend }

    var backendBadgeText: String {
        switch backendKind {
        case .pending:
            return "后端：初始化中"
        case .ghosttyMetal:
            return "后端：Ghostty Metal"
        case .unavailable:
            return "后端：不可用"
        }
    }

    static var isGhosttyAvailable: Bool {
        GhosttyApp.shared != nil
    }

    func start(
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws {
        if let app = GhosttyApp.shared {
            try startWithGhostty(
                app: app,
                executable: executable,
                arguments: arguments,
                workingDirectory: workingDirectory,
                environment: environment
            )
            return
        }

        let reason = GhosttyApp.unavailableReason
        backendKind = .unavailable
        backendMessage = reason
        throw CLITerminalError.launchFailed(
            "\(reason)。请先完成 GhosttyKit 构建并确认框架可加载。"
        )
    }

    func send(data: Data) {
        guard usesGhosttyBackend, let surface else { return }
        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty else { return }
        if isCommandSubmissionData(data) {
            lastSubmittedInputAt = Date()
            emitRuntimeStateHint(.working, minimumInterval: 0.10)
            markStrongWorking(at: Date.timeIntervalSinceReferenceDate)
        }
        surface.sendText(text)
    }

    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        guard usesGhosttyBackend else { return }
        // libghostty already receives pixel resize from host view layout.
    }

    func terminate() {
        stopActivityEvaluation()
        if let surface {
            surface.requestClose()
        } else {
            emitExitIfNeeded(exitCode: 1)
        }
    }

    /// Called by the NSView wrapper once the host view exists.
    func attachHostView(_ view: GhosttyTerminalSurfaceView) {
        Task { @MainActor [weak self] in
            self?.attachHostViewOnMain(view)
        }
    }

    /// Reuse one stable host view per session to avoid losing Ghostty surface
    /// binding when SwiftUI reconfigures hierarchy (e.g. single <-> split).
    @MainActor
    func reusableHostView(
        configure: (GhosttyTerminalSurfaceView) -> Void
    ) -> GhosttyTerminalSurfaceView {
        if let retainedHostView {
            configure(retainedHostView)
            return retainedHostView
        }

        let view = GhosttyTerminalSurfaceView(frame: .zero)
        configure(view)
        retainedHostView = view
        return view
    }

    /// Provides access so SwiftUI can attach the surface object.
    var ghosttySurface: GhosttySurface? { surface }

    /// Export-only text snapshot from the live Ghostty surface.
    func transcriptTextSnapshot() -> String? {
        if let liveSnapshot = surface?.readSurfaceTextSnapshot(),
           !liveSnapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return liveSnapshot
        }
        return lastNonEmptySurfaceSnapshotText
    }

    // Strong reference to keep callback bridge alive.
    private var delegateAdapter: GhosttyRunnerDelegate?

    deinit {
        pendingAttachWorkItem?.cancel()
        stopActivityEvaluation()
        surface?.requestClose()
        retainedHostView = nil
    }

    // MARK: - Ghostty path

    private func startWithGhostty(
        app: GhosttyApp,
        executable: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String]
    ) throws {
        usesGhosttyBackend = true
        backendKind = .ghosttyMetal
        backendMessage = nil
        ghosttyApp = app
        lastLaunchAt = Date()
        lastNonEmptySurfaceSnapshotText = nil
        waitingCandidateSince = 0
        lastPromptSignalAt = 0
        waitingStateLockedSince = 0
        runtimeStateProfile = determineRuntimeStateProfile(
            executable: executable,
            arguments: arguments
        )
        launchRequest = GhosttyLaunchRequest(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            environment: environment
        )
        startActivityEvaluation()

        if let hostView {
            attachHostView(hostView)
        }
    }

    @MainActor
    private func attachHostViewOnMain(_ view: GhosttyTerminalSurfaceView) {
        pendingAttachWorkItem?.cancel()
        hostView = view
        retainedHostView = view

        guard usesGhosttyBackend else { return }
        attachWhenHostViewReady(view, retryCount: 0)
    }

    @MainActor
    private func attachWhenHostViewReady(
        _ view: GhosttyTerminalSurfaceView,
        retryCount: Int
    ) {
        guard usesGhosttyBackend else { return }
        guard hostView === view else { return }

        let hasWindow = view.window != nil
        let hasUsableSize = view.bounds.width >= 2 && view.bounds.height >= 2
        if (!hasWindow || !hasUsableSize) && surface == nil {
            scheduleAttachRetry(for: view, retryCount: retryCount)
            return
        }

        do {
            try ensureGhosttySurface(on: view)
            if let surface {
                view.attachSurface(surface)
            }
        } catch {
            if retryCount < 10 {
                scheduleAttachRetry(for: view, retryCount: retryCount)
                return
            }
            backendKind = .unavailable
            backendMessage = error.localizedDescription
            let line = "\n[Ghostty] 启动失败：\(error.localizedDescription)\n"
            onOutput?(Data(line.utf8))
            emitExitIfNeeded(exitCode: 1)
        }
    }

    @MainActor
    private func scheduleAttachRetry(
        for view: GhosttyTerminalSurfaceView,
        retryCount: Int
    ) {
        guard retryCount < 60 else {
            backendKind = .unavailable
            let reason = "Ghostty 宿主视图尚未就绪（窗口或尺寸不可用）"
            backendMessage = reason
            onOutput?(Data("\n[Ghostty] \(reason)\n".utf8))
            emitExitIfNeeded(exitCode: 1)
            return
        }

        pendingAttachWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view else { return }
            Task { @MainActor in
                self.attachWhenHostViewReady(view, retryCount: retryCount + 1)
            }
        }
        pendingAttachWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    @MainActor
    private func ensureGhosttySurface(on view: GhosttyTerminalSurfaceView) throws {
        if let surface {
            view.attachSurface(surface)
            return
        }

        guard let app = ghosttyApp,
              let launchRequest
        else {
            return
        }

        guard let surface = GhosttySurface(
            app: app,
            hostView: view,
            command: launchRequest.command,
            workingDirectory: launchRequest.workingDirectory,
            environment: launchRequest.environment
        ) else {
            throw CLITerminalError.launchFailed("Ghostty surface 创建失败")
        }

        let delegateAdapter = GhosttyRunnerDelegate(runner: self)
        surface.delegate = delegateAdapter

        self.surface = surface
        self.delegateAdapter = delegateAdapter

    }
    // MARK: - Delegate bridge

    fileprivate func handleWorkingDirectoryChange(_ path: String) {
        onWorkingDirectoryChange?(path)
    }

    fileprivate func handleRenderFrame() {
        renderActivityTimeline.append(Date.timeIntervalSinceReferenceDate)
    }

    fileprivate func handlePromptTitleRequest(_ target: ghostty_action_prompt_title_e) {
        _ = target
    }

    fileprivate func handleSecureInput(_ mode: ghostty_action_secure_input_e) {
        if mode == GHOSTTY_SECURE_INPUT_ON {
            lastExplicitWaitingAt = Date()
            waitingStateLockedSince = Date.timeIntervalSinceReferenceDate
            emitRuntimeStateHint(.waitingUserInput)
        }
    }

    fileprivate func handleReadonly(_ mode: ghostty_action_readonly_e) {
        if mode == GHOSTTY_READONLY_ON {
            lastExplicitWaitingAt = Date()
            waitingStateLockedSince = Date.timeIntervalSinceReferenceDate
            emitRuntimeStateHint(.waitingUserInput)
        }
    }

    fileprivate func handleProgressReport(
        state: ghostty_action_progress_report_state_e,
        progress: Int8
    ) {
        _ = progress
        switch state {
        case GHOSTTY_PROGRESS_STATE_SET, GHOSTTY_PROGRESS_STATE_INDETERMINATE:
            lastProgressWorkingAt = Date()
            markStrongWorking(at: Date.timeIntervalSinceReferenceDate)
            emitRuntimeStateHint(.working, minimumInterval: 0.20)
        case GHOSTTY_PROGRESS_STATE_PAUSE, GHOSTTY_PROGRESS_STATE_REMOVE:
            lastExplicitWaitingAt = Date()
            waitingStateLockedSince = Date.timeIntervalSinceReferenceDate
            emitRuntimeStateHint(.waitingUserInput)
        case GHOSTTY_PROGRESS_STATE_ERROR:
            lastExplicitWaitingAt = Date()
            waitingStateLockedSince = Date.timeIntervalSinceReferenceDate
            emitRuntimeStateHint(.waitingUserInput)
        default:
            break
        }
    }

    fileprivate func handleCommandFinished(exitCode: Int16) {
        _ = exitCode
        lastExplicitWaitingAt = Date()
        waitingStateLockedSince = Date.timeIntervalSinceReferenceDate
        emitRuntimeStateHint(.waitingUserInput)
    }

    fileprivate func handleExit(code: Int32) {
        emitExitIfNeeded(exitCode: code)
    }

    private func emitExitIfNeeded(exitCode: Int32) {
        if let surface,
           let snapshot = surface.readSurfaceTextSnapshot(),
           !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastNonEmptySurfaceSnapshotText = snapshot
        }
        stopActivityEvaluation()
        exitLock.lock()
        if didEmitExit {
            exitLock.unlock()
            return
        }
        didEmitExit = true
        exitLock.unlock()

        onExit?(exitCode)
    }

    private func startActivityEvaluation() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopActivityEvaluation()

            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(
                deadline: .now() + .milliseconds(220),
                repeating: .milliseconds(260),
                leeway: .milliseconds(80)
            )
            timer.setEventHandler { [weak self] in
                self?.evaluateRuntimeStateFromAPISignals()
            }
            self.activityEvaluationTimer = timer
            timer.resume()
        }
    }

    private func stopActivityEvaluation() {
        if Thread.isMainThread {
            activityEvaluationTimer?.cancel()
            activityEvaluationTimer = nil
            renderActivityTimeline.removeAll(keepingCapacity: false)
            lastSurfaceSnapshotText = nil
            lastSurfaceSnapshotSampleAt = 0
            lastSurfaceTextChangedAt = 0
            waitingCandidateSince = 0
            lastPromptSignalAt = 0
            waitingStateLockedSince = 0
            return
        }
        DispatchQueue.main.sync {
            activityEvaluationTimer?.cancel()
            activityEvaluationTimer = nil
            renderActivityTimeline.removeAll(keepingCapacity: false)
            lastSurfaceSnapshotText = nil
            lastSurfaceSnapshotSampleAt = 0
            lastSurfaceTextChangedAt = 0
            waitingCandidateSince = 0
            lastPromptSignalAt = 0
            waitingStateLockedSince = 0
        }
    }

    private func evaluateRuntimeStateFromAPISignals() {
        guard usesGhosttyBackend else { return }
        guard let surface else { return }
        if surface.processExited() {
            return
        }

        let now = Date.timeIntervalSinceReferenceDate
        let renderWindow: TimeInterval = 1.20
        renderActivityTimeline.removeAll { now - $0 > renderWindow }
        let renderEventCount = renderActivityTimeline.count

        if surface.semanticPromptSeen() {
            semanticPromptObserved = true
        }

        let textActivityActive = observeSurfaceTextActivity(surface: surface, now: now)

        if now - lastSubmittedInputAt.timeIntervalSinceReferenceDate < 0.55 {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.08)
            return
        }

        if now - lastProgressWorkingAt.timeIntervalSinceReferenceDate < 1.30 {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.14)
            return
        }

        // Direct-launch CLIs (e.g. codex binary) may spend several seconds
        // in bootstrap before any stable semantic prompt signal appears.
        if now - lastLaunchAt.timeIntervalSinceReferenceDate < 8.0 {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.12)
            return
        }

        if runtimeStateProfile == .codex {
            evaluateCodexRuntimeState(
                now: now,
                surface: surface,
                textActivityActive: textActivityActive
            )
            return
        }

        if textActivityActive {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.10)
            return
        }

        if now - lastExplicitWaitingAt.timeIntervalSinceReferenceDate < 2.20 {
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.12)
            return
        }

        if semanticPromptObserved && surface.cursorIsAtPrompt() {
            lastExplicitWaitingAt = Date()
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.08)
            return
        }

        if semanticPromptObserved {
            switch surface.cursorSemanticContent() {
            case GHOSTTY_SURFACE_CURSOR_CONTENT_INPUT, GHOSTTY_SURFACE_CURSOR_CONTENT_PROMPT:
                lastExplicitWaitingAt = Date()
                emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.08)
                return
            case GHOSTTY_SURFACE_CURSOR_CONTENT_OUTPUT:
                markStrongWorking(at: now)
                emitRuntimeStateHint(.working, minimumInterval: 0.16)
                return
            default:
                break
            }
        }

        if now - lastSubmittedInputAt.timeIntervalSinceReferenceDate < 1.90 {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.24)
            return
        }

        if renderEventCount >= 4 {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.16)
            return
        }

        if renderEventCount <= 1 {
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.30)
            return
        }

        if semanticPromptObserved {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.24)
        } else {
            // No shell semantic prompt telemetry detected:
            // keep fallback conservative to avoid sticky "工作中".
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.30)
        }
    }

    private func evaluateCodexRuntimeState(
        now: TimeInterval,
        surface: GhosttySurface,
        textActivityActive: Bool
    ) {
        let promptSignalActive = isPromptSignalActive(surface: surface)
        if promptSignalActive {
            lastPromptSignalAt = now
            if waitingCandidateSince == 0 {
                waitingCandidateSince = now
            }
        } else if now - lastPromptSignalAt > 0.28 {
            waitingCandidateSince = 0
        }

        let quietFor: TimeInterval
        if lastSurfaceTextChangedAt > 0 {
            quietFor = now - lastSurfaceTextChangedAt
        } else {
            quietFor = now - lastLaunchAt.timeIntervalSinceReferenceDate
        }

        let submittedRecently = now - lastSubmittedInputAt.timeIntervalSinceReferenceDate < 0.75
        let progressWorkingRecently = now - lastProgressWorkingAt.timeIntervalSinceReferenceDate < 1.45
        let hasOutputAfterWaitingLock = waitingStateLockedSince > 0
            && lastSurfaceTextChangedAt > waitingStateLockedSince + 0.08

        if waitingStateLockedSince > 0 {
            if submittedRecently
                || progressWorkingRecently
                || (hasOutputAfterWaitingLock && !promptSignalActive) {
                waitingStateLockedSince = 0
                markStrongWorking(at: now)
                emitRuntimeStateHint(.working, minimumInterval: 0.08)
                return
            }
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.10)
            return
        }

        let hasStablePromptCandidate = promptSignalActive
            && waitingCandidateSince > 0
            && (now - waitingCandidateSince) >= 0.35
        let explicitWaitingStable = now - lastExplicitWaitingAt.timeIntervalSinceReferenceDate < 2.60
            && !submittedRecently
            && !progressWorkingRecently

        if hasStablePromptCandidate || explicitWaitingStable {
            waitingStateLockedSince = now
            lastExplicitWaitingAt = Date()
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.10)
            return
        }

        if submittedRecently || progressWorkingRecently || textActivityActive {
            markStrongWorking(at: now)
            emitRuntimeStateHint(.working, minimumInterval: 0.10)
            return
        }

        if quietFor >= 2.8 {
            emitRuntimeStateHint(.waitingUserInput, minimumInterval: 0.24)
            return
        }

        emitRuntimeStateHint(.working, minimumInterval: 0.12)
    }

    private func isPromptSignalActive(surface: GhosttySurface) -> Bool {
        if surface.cursorIsAtPrompt() {
            return true
        }
        switch surface.cursorSemanticContent() {
        case GHOSTTY_SURFACE_CURSOR_CONTENT_INPUT, GHOSTTY_SURFACE_CURSOR_CONTENT_PROMPT:
            return true
        default:
            return false
        }
    }

    private func markStrongWorking(at _: TimeInterval) {
        waitingCandidateSince = 0
        waitingStateLockedSince = 0
    }

    private func determineRuntimeStateProfile(
        executable: String,
        arguments: [String]
    ) -> RuntimeStateProfile {
        let executableName = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        if executableName == "codex" {
            return .codex
        }

        if executableName == "env",
           arguments.contains(where: { $0.lowercased() == "codex" }) {
            return .codex
        }

        if (executableName == "zsh" || executableName == "bash"),
           let commandLine = extractShellCommand(arguments: arguments) {
            let tokens = commandLine.split(whereSeparator: \.isWhitespace).map(String.init)
            for token in tokens {
                let normalized = token.lowercased()
                if normalized == "codex" || normalized.hasSuffix("/codex") {
                    return .codex
                }
                if normalized.contains("=") {
                    continue
                }
                break
            }
        }

        return .generic
    }

    private func extractShellCommand(arguments: [String]) -> String? {
        guard !arguments.isEmpty else { return nil }
        if arguments.count >= 2, arguments[0] == "-lc" || arguments[0] == "-c" {
            return arguments[1]
        }
        return arguments.last
    }

    private func observeSurfaceTextActivity(surface: GhosttySurface, now: TimeInterval) -> Bool {
        let sampleInterval: TimeInterval = 0.45
        if now - lastSurfaceSnapshotSampleAt >= sampleInterval {
            lastSurfaceSnapshotSampleAt = now
            if let snapshot = surface.readSurfaceTextSnapshot() {
                if !snapshot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lastNonEmptySurfaceSnapshotText = snapshot
                }
                if let previous = lastSurfaceSnapshotText {
                    if previous != snapshot {
                        lastSurfaceTextChangedAt = now
                    }
                } else if !snapshot.isEmpty {
                    lastSurfaceTextChangedAt = now
                }
                lastSurfaceSnapshotText = snapshot
            }
        }

        let activeWindow: TimeInterval = 1.40
        return now - lastSurfaceTextChangedAt < activeWindow
    }

    private func emitRuntimeStateHint(
        _ runtimeState: TerminalSessionRuntimeState,
        minimumInterval: TimeInterval = 0
    ) {
        let now = Date()
        if lastRuntimeHintState == runtimeState,
           now.timeIntervalSince(lastRuntimeHintAt) < minimumInterval {
            return
        }
        lastRuntimeHintState = runtimeState
        lastRuntimeHintAt = now
        onRuntimeStateHint?(runtimeState)
    }

    private func isCommandSubmissionData(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        if data.contains(0x03) || data.contains(0x04) {
            return true
        }
        return data.contains(0x0A) || data.contains(0x0D)
    }
}

// MARK: - GhosttyRunnerDelegate

private final class GhosttyRunnerDelegate: GhosttySurfaceDelegate {
    weak var runner: CLIGhosttyTerminalRunner?

    init(runner: CLIGhosttyTerminalRunner) {
        self.runner = runner
    }

    func surfaceDidUpdateTitle(_ title: String) {
        // Title is not currently surfaced in CLITerminalRunning.
    }

    func surfaceDidChangeWorkingDirectory(_ path: String) {
        runner?.handleWorkingDirectoryChange(path)
    }

    func surfaceDidExit(code: Int32) {
        runner?.handleExit(code: code)
    }

    func surfaceDidRenderFrame() {
        runner?.handleRenderFrame()
    }

    func surfaceDidRequestPromptTitle(_ target: ghostty_action_prompt_title_e) {
        runner?.handlePromptTitleRequest(target)
    }

    func surfaceDidReportProgress(state: ghostty_action_progress_report_state_e, progress: Int8) {
        runner?.handleProgressReport(state: state, progress: progress)
    }

    func surfaceDidSecureInput(_ mode: ghostty_action_secure_input_e) {
        runner?.handleSecureInput(mode)
    }

    func surfaceDidReadonly(_ mode: ghostty_action_readonly_e) {
        runner?.handleReadonly(mode)
    }

    func surfaceDidFinishCommand(exitCode: Int16) {
        runner?.handleCommandFinished(exitCode: exitCode)
    }
}

// MARK: - Helpers

private struct GhosttyLaunchRequest {
    let executable: String
    let arguments: [String]
    let workingDirectory: String
    let environment: [String: String]

    var command: String {
        ([executable] + arguments)
            .map(shellQuote)
            .joined(separator: " ")
    }
}

private func shellQuote(_ argument: String) -> String {
    if argument.isEmpty {
        return "''"
    }

    let safePattern = "^[A-Za-z0-9_@%+=:,./-]+$"
    if argument.range(of: safePattern, options: .regularExpression) != nil {
        return argument
    }

    return "'" + argument.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
}

private extension Optional where Wrapped == String {
    func withCString<T>(_ body: (UnsafePointer<CChar>?) -> T) -> T {
        if let value = self {
            return value.withCString(body)
        }
        return body(nil)
    }
}

private extension Array where Element == String {
    func withCStrings<T>(_ body: ([UnsafePointer<CChar>?]) -> T) -> T {
        if isEmpty {
            return body([])
        }

        func helper(index: Int, accumulated: [UnsafePointer<CChar>?]) -> T {
            if index == count {
                return body(accumulated)
            }

            return self[index].withCString { cStr in
                var next = accumulated
                next.append(cStr)
                return helper(index: index + 1, accumulated: next)
            }
        }

        return helper(index: 0, accumulated: [])
    }
}
