import Foundation
import Testing
@testable import AgentOS

struct CodexRuntimeStateMapperTests {
    @Test
    func parsesEventMsgEnvelopeFromSessionLogLine() {
        let line = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"1"}}"#
        let signal = CodexProtocolLineParser.parse(line: line)

        #expect(signal == .event(type: "task_started"))
    }

    @Test
    func parsesJSONRPCEventEnvelope() {
        let line = #"{"jsonrpc":"2.0","method":"codex/event","params":{"msg":{"type":"request_user_input"}}}"#
        let signal = CodexProtocolLineParser.parse(line: line)

        #expect(signal == .event(type: "request_user_input"))
    }

    @Test
    func mapsProtocolEventsToRuntimeState() {
        #expect(CodexRuntimeStateMapper.runtimeState(for: "task_started") == .working)
        #expect(CodexRuntimeStateMapper.runtimeState(for: "exec_approval_request") == .waitingApproval)
        #expect(CodexRuntimeStateMapper.runtimeState(for: "request_user_input") == .waitingUserInput)
        #expect(CodexRuntimeStateMapper.runtimeState(for: "turn/completed") == .waitingUserInput)
    }

    @Test
    func mapsJSONRPCMethodsToRuntimeState() {
        #expect(CodexRuntimeStateMapper.runtimeState(forMethod: "codex/event/task_complete") == .waitingUserInput)
        #expect(CodexRuntimeStateMapper.runtimeState(forMethod: "item/commandExecution/requestApproval") == .waitingApproval)
        #expect(CodexRuntimeStateMapper.runtimeState(forMethod: "turn/started") == .working)
        #expect(CodexRuntimeStateMapper.runtimeState(forMethod: "turn/completed") == .waitingUserInput)
        #expect(CodexRuntimeStateMapper.runtimeState(forMethod: "item/agentMessage/delta") == nil)
    }
}
