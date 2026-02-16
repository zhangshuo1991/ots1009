import Foundation
import AppKit

struct ToolInstallationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectAll() -> [ToolInstallation] {
        ProgrammingTool.allCases.map { detectInstallation($0) }
    }

    func detectInstallation(_ tool: ProgrammingTool) -> ToolInstallation {
        let detectionService = CLIDetectionService()
        let status = detectionService.detect(tool)
        let binaryPath = status.binaryPath

        let installMethod: InstallMethod
        let installLocation: String?

        if let path = binaryPath {
            installMethod = detectInstallMethod(path)
            installLocation = URL(fileURLWithPath: path).deletingLastPathComponent().path
        } else {
            installMethod = .unknown
            installLocation = nil
        }

        return ToolInstallation(
            tool: tool,
            binaryPath: binaryPath,
            isInstalled: binaryPath != nil,
            installMethod: installMethod,
            installLocation: installLocation,
            configPaths: tool.configPaths,
            version: status.version
        )
    }

    func detectInstallMethod(_ path: String) -> InstallMethod {
        let lowercased = path.lowercased()

        // Check for Homebrew
        if lowercased.contains("/opt/homebrew/") || lowercased.contains("/usr/local/homebrew/") {
            return .homebrew
        }

        // Check for npm/nvm/fnm
        if lowercased.contains("/.nvm/") || lowercased.contains("/.fnm/") ||
           lowercased.contains("/npm-global/") || lowercased.contains("/node_modules/") {
            return .npm
        }

        // Check for pip
        if lowercased.contains("/.local/") || lowercased.contains("/anaconda/") ||
           lowercased.contains("/miniconda/") {
            return .pip
        }

        // Check for Application folder (direct install)
        if lowercased.contains("/applications/") {
            return .direct
        }

        // Check if it's in common global bin directories
        let globalBins = ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        for bin in globalBins {
            if path.hasPrefix(bin) {
                return .homebrew
            }
        }

        return .unknown
    }

    func openConfigDirectory(for tool: ProgrammingTool) -> Bool {
        guard let firstPath = tool.configPaths.first else { return false }
        let configDir = (firstPath as NSString).deletingLastPathComponent
        return openDirectory(configDir)
    }

    func openInstallDirectory(for installation: ToolInstallation) -> Bool {
        guard let path = installation.installLocation else { return false }
        return openDirectory(path)
    }

    func updateTool(_ installation: ToolInstallation) async throws -> String {
        guard let command = installation.installMethod.updateCommand else {
            throw ToolInstallationError.unsupportedOperation("此安装方式不支持自动更新")
        }

        let packageName = installation.tool.npmPackageName ?? installation.tool.homebrewFormula ?? installation.tool.rawValue
        let fullCommand: String

        switch installation.installMethod {
        case .npm:
            fullCommand = "\(command) \(packageName)"
        case .homebrew:
            fullCommand = "\(command) \(packageName)"
        case .pip:
            fullCommand = "\(command) \(packageName)"
        default:
            throw ToolInstallationError.unsupportedOperation("无法自动更新")
        }

        return await runShellCommand(fullCommand)
    }

    func uninstallTool(_ installation: ToolInstallation) async throws -> String {
        guard let command = installation.installMethod.uninstallCommand else {
            throw ToolInstallationError.unsupportedOperation("此安装方式不支持自动卸载")
        }

        let packageName = installation.tool.npmPackageName ?? installation.tool.homebrewFormula ?? installation.tool.rawValue
        let fullCommand: String

        switch installation.installMethod {
        case .npm:
            fullCommand = "\(command) \(packageName)"
        case .homebrew:
            fullCommand = "\(command) \(packageName)"
        case .pip:
            fullCommand = "\(command) \(packageName)"
        default:
            throw ToolInstallationError.unsupportedOperation("无法自动卸载，请手动删除")
        }

        return await runShellCommand(fullCommand)
    }

    private func openDirectory(_ path: String) -> Bool {
        var expandedPath = path
        if path.hasPrefix("~") {
            expandedPath = (path as NSString).expandingTildeInPath
        }

        let url = URL(fileURLWithPath: expandedPath)
        return NSWorkspace.shared.open(url)
    }

    private func runShellCommand(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: output)
            } catch {
                continuation.resume(returning: "Error: \(error.localizedDescription)")
            }
        }
    }
}

enum ToolInstallationError: LocalizedError {
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let message):
            return message
        }
    }
}
