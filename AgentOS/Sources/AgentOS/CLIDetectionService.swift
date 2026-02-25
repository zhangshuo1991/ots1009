import Foundation

struct CLIDetectionService {
    typealias CommandRunner = (_ executable: String, _ args: [String]) -> String

    private let environment: [String: String]
    private let commandRunner: CommandRunner
    private let fileManager: FileManager
    private let homeDirectory: String
    private let fallbackDirectories: [String]

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        commandRunner: @escaping CommandRunner = CLIDetectionService.runProcess,
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory(),
        fallbackDirectories: [String]? = nil
    ) {
        self.environment = environment
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.fallbackDirectories = fallbackDirectories ?? [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/bin",
        ]
    }

    func detectAll() -> [ToolDetectionStatus] {
        ProgrammingTool.allCases.map(detect)
    }

    func detect(_ tool: ProgrammingTool) -> ToolDetectionStatus {
        for candidate in tool.candidates {
            if let path = resolveFromPathScan(candidate) {
                return ToolDetectionStatus(
                    id: tool,
                    tool: tool,
                    isInstalled: true,
                    binaryPath: path,
                    version: detectVersion(binaryPath: path, tool: tool),
                    source: .pathScan,
                    note: "通过 PATH 与常见目录检测到可执行文件。"
                )
            }

            if let path = resolveFromLoginShell(candidate, shell: "/bin/zsh") {
                return ToolDetectionStatus(
                    id: tool,
                    tool: tool,
                    isInstalled: true,
                    binaryPath: path,
                    version: detectVersion(binaryPath: path, tool: tool),
                    source: .zshLoginShell,
                    note: "通过 zsh 登录 shell 回退检测到可执行文件。"
                )
            }

            if let path = resolveFromLoginShell(candidate, shell: "/bin/bash") {
                return ToolDetectionStatus(
                    id: tool,
                    tool: tool,
                    isInstalled: true,
                    binaryPath: path,
                    version: detectVersion(binaryPath: path, tool: tool),
                    source: .bashLoginShell,
                    note: "通过 bash 登录 shell 回退检测到可执行文件。"
                )
            }
        }

        return ToolDetectionStatus(
            id: tool,
            tool: tool,
            isInstalled: false,
            binaryPath: nil,
            version: nil,
            source: .unknown,
            note: tool.installHint
        )
    }

    private func resolveFromPathScan(_ binary: String) -> String? {
        for directory in searchableDirectories() {
            let resolved = NSString(string: directory).appendingPathComponent(binary)
            if fileManager.isExecutableFile(atPath: resolved) {
                return resolved
            }
        }
        return nil
    }

    private func resolveFromLoginShell(_ binary: String, shell: String) -> String? {
        let output = commandRunner(shell, ["-lc", "command -v \(binary) 2>/dev/null"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return nil }
        return output.components(separatedBy: .newlines).first
    }

    private func detectVersion(binaryPath: String, tool: ProgrammingTool) -> String? {
        for args in tool.versionArguments {
            let output = commandRunner(binaryPath, args)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { continue }
            if let firstLine = output.components(separatedBy: .newlines).first,
               !firstLine.isEmpty
            {
                return firstLine
            }
        }
        return nil
    }

    private func searchableDirectories() -> [String] {
        let pathEntries = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        let uvToolDirectories = uvToolBinDirectories()

        var ordered: [String] = []
        for entry in pathEntries + fallbackDirectories + uvToolDirectories where !ordered.contains(entry) {
            ordered.append(entry)
        }
        return ordered
    }

    private func uvToolBinDirectories() -> [String] {
        let baseCandidates = uvToolsRootCandidates()
        var directories: [String] = []

        for base in baseCandidates {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: base, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            guard let toolEnvironments = try? fileManager.contentsOfDirectory(atPath: base) else { continue }
            for toolEnv in toolEnvironments {
                let binDirectory = NSString(string: base)
                    .appendingPathComponent(toolEnv)
                    .appending("/bin")
                var isBinDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: binDirectory, isDirectory: &isBinDirectory),
                      isBinDirectory.boolValue
                else {
                    continue
                }
                if !directories.contains(binDirectory) {
                    directories.append(binDirectory)
                }
            }
        }

        return directories
    }

    private func uvToolsRootCandidates() -> [String] {
        var candidates: [String] = []

        if let uvToolDir = environment["UV_TOOL_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uvToolDir.isEmpty
        {
            candidates.append(uvToolDir)
        }

        if let xdgDataHome = environment["XDG_DATA_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xdgDataHome.isEmpty
        {
            candidates.append("\(xdgDataHome)/uv/tools")
        }

        candidates.append("\(homeDirectory)/.local/share/uv/tools")

        var ordered: [String] = []
        for candidate in candidates where !ordered.contains(candidate) {
            ordered.append(candidate)
        }
        return ordered
    }

    private static func runProcess(_ executable: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }
}
