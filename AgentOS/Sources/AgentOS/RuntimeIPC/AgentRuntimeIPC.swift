import Darwin
import Foundation

enum AgentTaskStatus: String, Codable, Sendable {
    case thinking
    case callingTool = "calling_tool"
    case awaitingUser = "awaiting_user"
    case approving
    case streaming
}

struct AgentRuntimeIPCEvent: Codable, Sendable {
    let status: AgentTaskStatus
    let message: String?
    let approvalPrompt: String?
    let timestamp: String?
    let tool: String?

    var runtimeState: TerminalSessionRuntimeState {
        switch status {
        case .thinking, .callingTool, .streaming:
            return .working
        case .awaitingUser:
            return .waitingUserInput
        case .approving:
            return .waitingApproval
        }
    }
}

struct TerminalApprovalRequest: Equatable, Sendable {
    let prompt: String
    let receivedAt: Date
}

protocol AgentRuntimeIPCServing: AnyObject {
    var socketPath: String { get }
    func start() throws
    func stop()
}

final class AgentRuntimeIPCServer: AgentRuntimeIPCServing, @unchecked Sendable {
    struct Configuration {
        let socketPath: String
        let onEvent: @Sendable (AgentRuntimeIPCEvent) -> Void
        let onError: @Sendable (String) -> Void
    }

    let socketPath: String

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "agentos.runtime.ipc.server.\(UUID().uuidString)")
    private let decoder = JSONDecoder()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]

    init(configuration: Configuration) {
        self.configuration = configuration
        self.socketPath = configuration.socketPath
    }

    deinit {
        stop()
    }

    func start() throws {
        guard acceptSource == nil else { return }
        try prepareSocketDirectoryIfNeeded()
        cleanupStaleSocketIfNeeded()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLITerminalError.launchFailed("IPC socket 创建失败(errno=\(errno))")
        }
        listenFD = fd
        setNonBlocking(fd)

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(socketPath.utf8CString)
        let sunPathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= sunPathCapacity else {
            Darwin.close(fd)
            listenFD = -1
            throw CLITerminalError.launchFailed("IPC socket 路径过长：\(socketPath)")
        }

        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: UInt8.self, repeating: 0)
            for (index, byte) in pathBytes.enumerated() {
                rawBuffer[index] = UInt8(bitPattern: byte)
            }
        }

        let addressLength = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + pathBytes.count)
        let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, addressLength)
            }
        }
        guard bindResult == 0 else {
            let code = errno
            Darwin.close(fd)
            listenFD = -1
            throw CLITerminalError.launchFailed("IPC socket 绑定失败(errno=\(code))")
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let code = errno
            Darwin.close(fd)
            listenFD = -1
            throw CLITerminalError.launchFailed("IPC socket 监听失败(errno=\(code))")
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenFD >= 0 {
                Darwin.close(self.listenFD)
                self.listenFD = -1
            }
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        for source in clientSources.values {
            source.cancel()
        }
        clientSources = [:]
        clientBuffers = [:]

        acceptSource?.cancel()
        acceptSource = nil

        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func prepareSocketDirectoryIfNeeded() throws {
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        guard !directory.path.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw CLITerminalError.launchFailed("IPC 目录创建失败：\(error.localizedDescription)")
        }
    }

    private func cleanupStaleSocketIfNeeded() {
        unlink(socketPath)
    }

    private func acceptPendingClients() {
        guard listenFD >= 0 else { return }

        while true {
            var storage = sockaddr()
            var length = socklen_t(MemoryLayout.size(ofValue: storage))
            let clientFD = withUnsafeMutablePointer(to: &storage) { pointer -> Int32 in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    accept(listenFD, sockaddrPointer, &length)
                }
            }

            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                configuration.onError("IPC 接入失败(errno=\(errno))")
                break
            }

            setNonBlocking(clientFD)
            let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
            source.setEventHandler { [weak self] in
                self?.readClient(fd: clientFD)
            }
            source.setCancelHandler { [weak self] in
                Darwin.close(clientFD)
                self?.clientBuffers.removeValue(forKey: clientFD)
                self?.clientSources.removeValue(forKey: clientFD)
            }
            clientBuffers[clientFD] = Data()
            clientSources[clientFD] = source
            source.resume()
        }
    }

    private func readClient(fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4_096)

        while true {
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                var buffer = clientBuffers[fd] ?? Data()
                buffer.append(chunk, count: count)
                consumeLines(from: &buffer)
                clientBuffers[fd] = buffer
                continue
            }

            if count == 0 {
                closeClient(fd)
                return
            }

            if errno == EWOULDBLOCK || errno == EAGAIN {
                return
            }

            configuration.onError("IPC 读取失败(errno=\(errno))")
            closeClient(fd)
            return
        }
    }

    private func closeClient(_ fd: Int32) {
        guard let source = clientSources[fd] else {
            Darwin.close(fd)
            clientBuffers.removeValue(forKey: fd)
            return
        }
        source.cancel()
    }

    private func consumeLines(from buffer: inout Data) {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: 0..<newlineIndex)
            buffer.removeSubrange(0...newlineIndex)
            if line.last == 0x0D {
                line.removeLast()
            }
            guard !line.isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ line: Data) {
        guard let event = try? decoder.decode(AgentRuntimeIPCEvent.self, from: line) else {
            let preview = String(decoding: line.prefix(200), as: UTF8.self)
            configuration.onError("IPC 事件解析失败：\(preview)")
            return
        }
        configuration.onEvent(event)
    }

    private func setNonBlocking(_ fd: Int32) {
        let currentFlags = fcntl(fd, F_GETFL)
        guard currentFlags >= 0 else { return }
        _ = fcntl(fd, F_SETFL, currentFlags | O_NONBLOCK)
    }
}
