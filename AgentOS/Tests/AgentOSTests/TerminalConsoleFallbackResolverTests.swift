import Foundation
import Testing
@testable import AgentOS

struct TerminalConsoleFallbackResolverTests {
    @Test
    func runningSessionWithoutRunnerUsesLaunchingState() {
        let session = makeSession(isRunning: true, output: "booting")
        let state = TerminalConsoleFallbackResolver.resolve(session: session, hasRunner: false)
        #expect(state == .launching)
    }

    @Test
    func endedSessionWithoutOutputUsesUnavailableState() {
        let session = makeSession(isRunning: false, output: "")
        let state = TerminalConsoleFallbackResolver.resolve(session: session, hasRunner: false)
        #expect(state == .unavailable)
    }

    @Test
    func endedSessionUsesSanitizedTranscript() {
        let ansi = "\u{001B}[1;32m完成\u{001B}[0m\n第二行输出\n"
        let session = makeSession(isRunning: false, output: ansi)
        let state = TerminalConsoleFallbackResolver.resolve(
            session: session,
            hasRunner: false,
            maxTranscriptCharacters: 64
        )

        guard case .transcript(let transcript) = state else {
            Issue.record("期望 transcript 状态，实际为 \(state)")
            return
        }
        #expect(transcript.contains("完成"))
        #expect(transcript.contains("第二行输出"))
        #expect(!transcript.contains("\u{001B}"))
    }

    @Test
    func transcriptRespectsMaxCharacters() {
        let output = "header\n" + String(repeating: "a", count: 120)
        let session = makeSession(isRunning: false, output: output)
        let state = TerminalConsoleFallbackResolver.resolve(
            session: session,
            hasRunner: false,
            maxTranscriptCharacters: 32
        )

        guard case .transcript(let transcript) = state else {
            Issue.record("期望 transcript 状态，实际为 \(state)")
            return
        }
        #expect(transcript.count <= 32)
    }

    private func makeSession(isRunning: Bool, output: String) -> CLITerminalSession {
        let buffer = TerminalSessionOutputBuffer(
            maxBytes: 1_200_000,
            maxPreviewCharacters: 4_096
        )
        if !output.isEmpty {
            buffer.append(Data(output.utf8))
        }
        let now = Date()
        return CLITerminalSession(
            id: UUID(),
            tool: .codex,
            title: "Test Session",
            executable: "/usr/bin/env",
            arguments: ["codex"],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            createdAt: now,
            updatedAt: now,
            startedAt: now,
            endedAt: isRunning ? nil : now,
            isRunning: isRunning,
            exitCode: isRunning ? nil : 0,
            outputBuffer: buffer,
            lastInput: nil,
            isRestoredSnapshot: false,
            transcriptFilePath: nil,
            codexConversationID: nil
        )
    }
}
