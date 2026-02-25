import AppKit
import GhosttyKit
import Metal
import QuartzCore
import SwiftUI

// MARK: - GhosttyTerminalSurfaceView (NSView) — Metal mode

/// NSView subclass that hosts a libghostty Metal-rendered terminal surface.
///
/// libghostty owns the Metal device, command queue, and render pipeline.  We
/// provide a `CAMetalLayer` for it to render into, and forward keyboard /
/// mouse / resize events to the `GhosttySurface` handle.
@MainActor
final class GhosttyTerminalSurfaceView: NSView, @preconcurrency NSTextInputClient {
    private weak var surface: GhosttySurface?
    private var metalLayer: CAMetalLayer?
    private var onSendData: ((Data) -> Void)?
    private var isRunningTerminal = false
    private var markedTextStorage = NSAttributedString(string: "")
    private var selectedTextRange = NSRange(location: NSNotFound, length: 0)
    private var deferredResyncWorkItem: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupMetalLayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    func configure(
        onSendData: @escaping (Data) -> Void,
        onResize _: @escaping (Int, Int) -> Void,
        isRunning: Bool
    ) {
        self.onSendData = onSendData
        self.isRunningTerminal = isRunning
    }

    /// Attach a `GhosttySurface` to this view. The surface's Metal renderer
    /// will target our `CAMetalLayer`.
    func attachSurface(_ surface: GhosttySurface) {
        self.surface = surface
        requestStableResync()
        surface.setFocused(window?.firstResponder === self)
    }

    // MARK: - Metal Layer

    private func setupMetalLayer() {
        let metal = CAMetalLayer()
        metal.device = MTLCreateSystemDefaultDevice()
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.contentsScale = window?.backingScaleFactor ?? 2.0
        metal.frame = bounds

        layer = metal
        metalLayer = metal
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        metalLayer?.frame = bounds
        updateSurfaceSize()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        requestStableResync()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        requestStableResync()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        requestStableResync()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentScale()
        updateSurfaceSize(forceRender: true)
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        // Prime an immediate frame so dragging starts from fresh content.
        surface?.draw()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // Ensure the final window size has a fully refreshed frame.
        updateSurfaceSize(forceRender: true)
    }

    private func updateSurfaceSize(forceRender: Bool = false) {
        guard let metalLayer else { return }
        guard window != nil else { return }
        guard !isHiddenOrHasHiddenAncestor else { return }
        guard bounds.width >= 4, bounds.height >= 4 else { return }

        let scale = metalLayer.contentsScale
        let pixelWidth = UInt32((bounds.width * scale).rounded(.down))
        let pixelHeight = UInt32((bounds.height * scale).rounded(.down))
        guard pixelWidth >= 2, pixelHeight >= 2 else { return }
        let targetDrawableSize = CGSize(width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        let drawableSizeChanged = metalLayer.drawableSize != targetDrawableSize
        if drawableSizeChanged {
            metalLayer.drawableSize = targetDrawableSize
        }

        if drawableSizeChanged || forceRender {
            surface?.resize(width: pixelWidth, height: pixelHeight)
        }

        if inLiveResize || window?.inLiveResize == true || drawableSizeChanged || forceRender {
            surface?.draw()
        }
    }

    private func updateContentScale() {
        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer?.contentsScale = scale
        surface?.setContentScale(x: scale, y: scale)
    }

    func requestStableResync() {
        updateContentScale()
        updateSurfaceSize(forceRender: true)

        deferredResyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.updateContentScale()
            self.updateSurfaceSize(forceRender: true)
        }
        deferredResyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    // MARK: - Keyboard Input

    override func keyDown(with event: NSEvent) {
        guard !handleCommandShortcut(event) else { return }

        // Keep IME composition state authoritative: while marked text exists,
        // route key events (including delete) through the input method.
        if hasMarkedText() {
            interpretKeyEvents([event])
            return
        }

        // Forward to surface if available
        if surface != nil {
            if shouldUseTextInputSystem(for: event) {
                interpretKeyEvents([event])
                return
            }
            sendGhosttyKeyEvent(
                event,
                action: event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
            )
            return
        }

        // Fallback: direct data send for compatibility
        if event.modifierFlags.contains(.control),
           let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first,
           scalar.value >= 0x61, scalar.value <= 0x7A {
            let control = UInt8(scalar.value - 0x60)
            onSendData?(Data([control]))
            return
        }

        switch event.keyCode {
        case 36: onSendData?(Data("\r".utf8))
        case 48: onSendData?(Data("\t".utf8))
        case 51: onSendData?(Data([0x7F]))
        case 53: onSendData?(Data([0x1B]))
        case 123: onSendData?(Data("\u{001B}[D".utf8))
        case 124: onSendData?(Data("\u{001B}[C".utf8))
        case 125: onSendData?(Data("\u{001B}[B".utf8))
        case 126: onSendData?(Data("\u{001B}[A".utf8))
        default:
            if let chars = event.characters, !chars.isEmpty {
                onSendData?(Data(chars.utf8))
            }
        }
    }

    private func shouldUseTextInputSystem(for event: NSEvent) -> Bool {
        let terminalModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard terminalModifiers.isEmpty else { return false }

        switch event.keyCode {
        case 36, 48, 51, 53, 123, 124, 125, 126:
            return false
        default:
            break
        }

        guard let characters = event.characters, !characters.isEmpty else {
            return false
        }

        let hasFunctionScalars = characters.unicodeScalars.contains { scalar in
            scalar.value >= 0xF700 && scalar.value <= 0xF8FF
        }
        return !hasFunctionScalars
    }

    override func keyUp(with event: NSEvent) {
        guard surface != nil else { return }
        sendGhosttyKeyEvent(event, action: GHOSTTY_ACTION_RELEASE)
    }

    override func flagsChanged(with event: NSEvent) {
        guard surface != nil else { return }
        guard let modifierMask = modifierMaskForFlagsChanged(keyCode: event.keyCode) else { return }

        let mods = mapModifiers(event.modifierFlags)
        let isPressed = (mods.rawValue & modifierMask) != 0
        let action: ghostty_input_action_e = isPressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE
        sendGhosttyKeyEvent(event, action: action)
    }

    private func handleCommandShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }

        if key == "v", let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            if let surface {
                surface.sendText(text)
            } else {
                onSendData?(Data(text.utf8))
            }
            return true
        }
        return false
    }

    private func sendGhosttyKeyEvent(
        _ event: NSEvent,
        action: ghostty_input_action_e,
        composing: Bool = false
    ) {
        guard let surface else { return }

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)

        let mods = mapModifiers(event.modifierFlags)
        keyEvent.mods = mods
        keyEvent.consumed_mods = surface.translateModifiers(mods)
        keyEvent.composing = composing

        if let unshifted = event.characters(byApplyingModifiers: []),
           let scalar = unshifted.unicodeScalars.first {
            keyEvent.unshifted_codepoint = scalar.value
        } else {
            keyEvent.unshifted_codepoint = 0
        }

        if let text = ghosttyText(for: event), !text.isEmpty {
            text.withCString { textPtr in
                keyEvent.text = textPtr
                surface.sendKeyEvent(keyEvent)
            }
        } else {
            keyEvent.text = nil
            surface.sendKeyEvent(keyEvent)
        }
    }

    private func ghosttyText(for event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }

        if characters.count == 1,
           let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }

        return characters
    }

    private func mapModifiers(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue

        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }

        let rawFlags = flags.rawValue
        if rawFlags & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCTLKEYMASK) != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERALTKEYMASK) != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if rawFlags & UInt(NX_DEVICERCMDKEYMASK) != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }

        return ghostty_input_mods_e(mods)
    }

    private func modifierMaskForFlagsChanged(keyCode: UInt16) -> UInt32? {
        switch keyCode {
        case 0x39: return GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: return GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: return GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: return GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: return GHOSTTY_MODS_SUPER.rawValue
        default: return nil
        }
    }

    // MARK: - Mouse Input

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseUp(with event: NSEvent) {
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_LEFT)
    }

    override func mouseDragged(with event: NSEvent) {
        forwardMousePositionEvent(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_PRESS, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func rightMouseUp(with event: NSEvent) {
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_RELEASE, button: GHOSTTY_MOUSE_RIGHT)
    }

    override func otherMouseDown(with event: NSEvent) {
        let button = mouseButton(for: event.buttonNumber)
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_PRESS, button: button)
    }

    override func otherMouseUp(with event: NSEvent) {
        let button = mouseButton(for: event.buttonNumber)
        forwardMouseButtonEvent(event, state: GHOSTTY_MOUSE_RELEASE, button: button)
    }

    override func rightMouseDragged(with event: NSEvent) {
        forwardMousePositionEvent(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        forwardMousePositionEvent(event)
    }

    override func scrollWheel(with event: NSEvent) {
        surface?.sendMouseScroll(
            x: event.scrollingDeltaX,
            y: event.scrollingDeltaY,
            modifiers: scrollModifiers(for: event)
        )
    }

    private func forwardMouseButtonEvent(
        _ event: NSEvent,
        state: ghostty_input_mouse_state_e,
        button: ghostty_input_mouse_button_e
    ) {
        guard let surface else { return }
        let position = terminalCoordinates(for: event)
        let mods = mapModifiers(event.modifierFlags)
        surface.sendMousePosition(x: position.x, y: position.y, modifiers: mods)
        surface.sendMouseButton(
            state: state,
            button: button,
            modifiers: mods
        )
    }

    private func forwardMousePositionEvent(_ event: NSEvent) {
        guard let surface else { return }
        let position = terminalCoordinates(for: event)
        surface.sendMousePosition(
            x: position.x,
            y: position.y,
            modifiers: mapModifiers(event.modifierFlags)
        )
    }

    private func terminalCoordinates(for event: NSEvent) -> (x: Double, y: Double) {
        let location = convert(event.locationInWindow, from: nil)
        return (location.x, bounds.height - location.y)
    }

    private func mouseButton(for buttonNumber: Int) -> ghostty_input_mouse_button_e {
        switch buttonNumber {
        case 0: return GHOSTTY_MOUSE_LEFT
        case 1: return GHOSTTY_MOUSE_RIGHT
        case 2: return GHOSTTY_MOUSE_MIDDLE
        case 3: return GHOSTTY_MOUSE_EIGHT
        case 4: return GHOSTTY_MOUSE_NINE
        case 5: return GHOSTTY_MOUSE_SIX
        case 6: return GHOSTTY_MOUSE_SEVEN
        case 7: return GHOSTTY_MOUSE_FOUR
        case 8: return GHOSTTY_MOUSE_FIVE
        case 9: return GHOSTTY_MOUSE_TEN
        case 10: return GHOSTTY_MOUSE_ELEVEN
        default: return GHOSTTY_MOUSE_UNKNOWN
        }
    }

    private func scrollModifiers(for event: NSEvent) -> ghostty_input_scroll_mods_t {
        var value: Int32 = 0
        if event.hasPreciseScrollingDeltas {
            value |= 0b0000_0001
        }

        let momentum: Int32
        switch event.momentumPhase {
        case .began: momentum = 1
        case .stationary: momentum = 2
        case .changed: momentum = 3
        case .ended: momentum = 4
        case .cancelled: momentum = 5
        case .mayBegin: momentum = 6
        default: momentum = 0
        }

        value |= (momentum << 1)
        return ghostty_input_scroll_mods_t(value)
    }

    // MARK: - Focus

    override func becomeFirstResponder() -> Bool {
        surface?.setFocused(true)
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        surface?.setFocused(false)
        return super.resignFirstResponder()
    }

    // MARK: - NSTextInputClient

    func insertText(_ string: Any, replacementRange: NSRange) {
        let text: String
        if let attributed = string as? NSAttributedString {
            text = attributed.string
        } else if let plain = string as? String {
            text = plain
        } else {
            return
        }

        guard !text.isEmpty else { return }
        markedTextStorage = NSAttributedString(string: "")
        selectedTextRange = NSRange(location: NSNotFound, length: 0)

        if let surface {
            surface.sendText(text)
        } else {
            onSendData?(Data(text.utf8))
        }
    }

    override func doCommand(by selector: Selector) {
        // During IME composition, command events should be consumed by the
        // input method instead of being forwarded to terminal control bytes.
        if hasMarkedText() {
            return
        }

        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onSendData?(Data("\r".utf8))
        case #selector(NSResponder.insertTab(_:)):
            onSendData?(Data("\t".utf8))
        case #selector(NSResponder.deleteBackward(_:)):
            onSendData?(Data([0x7F]))
        case #selector(NSResponder.cancelOperation(_:)):
            onSendData?(Data([0x1B]))
        case #selector(NSResponder.moveLeft(_:)):
            onSendData?(Data("\u{001B}[D".utf8))
        case #selector(NSResponder.moveRight(_:)):
            onSendData?(Data("\u{001B}[C".utf8))
        case #selector(NSResponder.moveDown(_:)):
            onSendData?(Data("\u{001B}[B".utf8))
        case #selector(NSResponder.moveUp(_:)):
            onSendData?(Data("\u{001B}[A".utf8))
        default:
            break
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if let attributed = string as? NSAttributedString {
            markedTextStorage = attributed
        } else if let plain = string as? String {
            markedTextStorage = NSAttributedString(string: plain)
        } else {
            markedTextStorage = NSAttributedString(string: "")
        }
        selectedTextRange = selectedRange
    }

    func unmarkText() {
        markedTextStorage = NSAttributedString(string: "")
        selectedTextRange = NSRange(location: NSNotFound, length: 0)
    }

    func selectedRange() -> NSRange {
        selectedTextRange
    }

    func markedRange() -> NSRange {
        guard hasMarkedText() else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedTextStorage.length)
    }

    func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        actualRange?.pointee = NSRange(location: NSNotFound, length: 0)
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        actualRange?.pointee = range
        guard let window else { return .zero }
        // Keep IME candidate popup close to terminal input area instead of top-left.
        let localRect = NSRect(x: bounds.minX + 12, y: bounds.minY + 8, width: 1, height: 20)
        let rectInWindow = convert(localRect, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    func characterIndex(for point: NSPoint) -> Int {
        NSNotFound
    }
}

// MARK: - GhosttyTerminalEmulatorView (NSViewRepresentable)

/// SwiftUI wrapper for Ghostty Metal mode only.
struct GhosttyTerminalEmulatorView: NSViewRepresentable {
    let sessionID: UUID
    let runner: CLIGhosttyTerminalRunner
    let isRunning: Bool
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionID: sessionID)
    }

    func makeNSView(context: Context) -> GhosttyTerminalSurfaceView {
        makeMetalView(context: context)
    }

    func updateNSView(_ nsView: GhosttyTerminalSurfaceView, context: Context) {
        nsView.configure(onSendData: onSendData, onResize: onResize, isRunning: isRunning)

        runner.attachHostView(nsView)
        if let surface = runner.ghosttySurface {
            nsView.attachSurface(surface)
        }
        nsView.requestStableResync()

        if context.coordinator.sessionID != sessionID {
            context.coordinator.sessionID = sessionID
        }

        if isRunning, nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    // MARK: - Factory helpers

    private func makeMetalView(context: Context) -> GhosttyTerminalSurfaceView {
        let view = runner.reusableHostView { hostView in
            hostView.configure(onSendData: onSendData, onResize: onResize, isRunning: isRunning)
        }
        runner.attachHostView(view)
        if let surface = runner.ghosttySurface {
            view.attachSurface(surface)
        }
        return view
    }

    // MARK: - Coordinator

    final class Coordinator {
        var sessionID: UUID
        init(sessionID: UUID) {
            self.sessionID = sessionID
        }
    }
}
