import Foundation

enum CodexRuntimeStateMapper {
    private static let workingEventTypes: Set<String> = [
        "task_started",
        "turn_started",
        "turn/started",
        "thread/started",
        "item_started",
        "item/started",
        "exec_command_begin",
        "mcp_tool_call_begin",
        "web_search_begin",
        "patch_apply_begin",
        "collab_waiting_begin",
        "item/tool/call",
    ]

    private static let waitingApprovalEventTypes: Set<String> = [
        "exec_approval_request",
        "apply_patch_approval_request",
        "item/commandexecution/requestapproval",
        "item/filechange/requestapproval",
        "execcommandapproval",
        "applypatchapproval",
        "commandexecutionrequestapproval",
        "filechangerequestapproval",
    ]

    private static let waitingInputEventTypes: Set<String> = [
        "task_complete",
        "turn_complete",
        "turn/completed",
        "turn_aborted",
        "request_user_input",
        "item/tool/requestuserinput",
        "shutdown_complete",
        "shutdowncomplete",
        "requestuserinput",
        "toolrequestuserinput",
    ]

    static func runtimeState(for signal: CodexProtocolSignal) -> TerminalSessionRuntimeState? {
        switch signal {
        case .sessionMeta:
            return nil
        case .event(let eventType):
            return runtimeState(for: eventType)
        }
    }

    static func runtimeState(for rawEventType: String) -> TerminalSessionRuntimeState? {
        let normalized = rawEventType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }

        if waitingApprovalEventTypes.contains(normalized) {
            return .waitingApproval
        }

        if waitingInputEventTypes.contains(normalized) {
            return .waitingUserInput
        }

        if workingEventTypes.contains(normalized) {
            return .working
        }

        return nil
    }

    static func runtimeState(forMethod rawMethod: String) -> TerminalSessionRuntimeState? {
        let normalizedMethod = rawMethod
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedMethod.isEmpty else { return nil }

        if normalizedMethod.hasPrefix("codex/event/") {
            let eventType = String(normalizedMethod.dropFirst("codex/event/".count))
            return runtimeState(for: eventType)
        }

        return runtimeState(for: normalizedMethod)
    }
}
