import Foundation
import AppKit

struct ToolInstallationService {
    private let fileManager: FileManager
    private let detectionService: CLIDetectionService
    private let shellCommandRunner: (String) -> String
    private let adminShellCommandRunner: (String) -> String

    init(
        fileManager: FileManager = .default,
        detectionService: CLIDetectionService = CLIDetectionService(),
        shellCommandRunner: @escaping (String) -> String = { command in
            ToolInstallationService.runShellCommandSync(command)
        },
        adminShellCommandRunner: @escaping (String) -> String = { command in
            ToolInstallationService.runShellCommandAsAdministratorSync(command)
        }
    ) {
        self.fileManager = fileManager
        self.detectionService = detectionService
        self.shellCommandRunner = shellCommandRunner
        self.adminShellCommandRunner = adminShellCommandRunner
    }

    func detectAll() -> [ToolInstallation] {
        ProgrammingTool.allCases.map { detectInstallation($0) }
    }

    func detectInstallation(_ tool: ProgrammingTool) -> ToolInstallation {
        let status = detectionService.detect(tool)
        let binaryPath = status.binaryPath

        let installMethod: InstallMethod
        let installLocation: String?
        var version = normalizedVersion(status.version)

        if let path = binaryPath {
            let resolvedBinaryPath = resolveBinaryPath(path)
            installMethod = detectInstallMethod(resolvedBinaryPath ?? path)
            installLocation = detectInstallLocation(
                tool: tool,
                binaryPath: path,
                resolvedBinaryPath: resolvedBinaryPath,
                installMethod: installMethod
            )

            if version == nil {
                version = fallbackVersion(
                    for: tool,
                    installMethod: installMethod,
                    binaryPath: path,
                    resolvedBinaryPath: resolvedBinaryPath,
                    installLocation: installLocation
                )
            }
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
            version: version
        )
    }

    private func resolveBinaryPath(_ path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return resolved.isEmpty ? nil : resolved
    }

    private func detectInstallLocation(
        tool: ProgrammingTool,
        binaryPath: String,
        resolvedBinaryPath: String?,
        installMethod: InstallMethod
    ) -> String {
        switch installMethod {
        case .npm:
            if let location = npmPackageDirectory(from: resolvedBinaryPath ?? binaryPath, tool: tool) {
                return location
            }

            if let inferred = inferNpmPackageDirectory(fromBinaryPath: binaryPath, tool: tool) {
                return inferred
            }

            return URL(fileURLWithPath: resolvedBinaryPath ?? binaryPath).deletingLastPathComponent().path
        default:
            let path = resolvedBinaryPath ?? binaryPath
            if let appRoot = appBundleRoot(from: path) {
                return appRoot
            }
            return URL(fileURLWithPath: path).deletingLastPathComponent().path
        }
    }

    private func appBundleRoot(from path: String) -> String? {
        let marker = ".app/Contents/MacOS/"
        guard let range = path.range(of: marker, options: [.caseInsensitive]) else { return nil }
        return String(path[..<range.upperBound]).replacingOccurrences(of: "/Contents/MacOS/", with: "")
    }

    private func npmPackageDirectory(from path: String, tool: ProgrammingTool) -> String? {
        guard let nodeModulesRange = path.range(of: "/node_modules/") else { return nil }

        let prefix = String(path[..<nodeModulesRange.upperBound])
        let suffixComponents = path[nodeModulesRange.upperBound...].split(separator: "/")
        guard !suffixComponents.isEmpty else { return nil }

        let packageComponentCount = suffixComponents[0].hasPrefix("@") ? 2 : 1
        guard suffixComponents.count >= packageComponentCount else { return nil }

        let detectedPackage = suffixComponents.prefix(packageComponentCount).joined(separator: "/")
        guard !detectedPackage.hasPrefix(".") else { return nil }

        if let expectedPackage = tool.npmPackageName, detectedPackage != expectedPackage {
            return nil
        }

        return prefix + detectedPackage
    }

    private func inferNpmPackageDirectory(fromBinaryPath path: String, tool: ProgrammingTool) -> String? {
        guard let packageName = tool.npmPackageName else { return nil }

        let binaryDir = URL(fileURLWithPath: path).deletingLastPathComponent().path
        guard binaryDir.hasSuffix("/bin") else { return nil }

        let prefix = String(binaryDir.dropLast(4))
        let candidate = "\(prefix)/lib/node_modules/\(packageName)"
        return fileManager.fileExists(atPath: candidate) ? candidate : nil
    }

    private func fallbackVersion(
        for tool: ProgrammingTool,
        installMethod: InstallMethod,
        binaryPath: String,
        resolvedBinaryPath: String?,
        installLocation: String?
    ) -> String? {
        switch installMethod {
        case .npm:
            if let packageVersion = readNpmPackageVersion(
                tool: tool,
                binaryPath: binaryPath,
                resolvedBinaryPath: resolvedBinaryPath,
                installLocation: installLocation
            ) {
                return packageVersion
            }
            return getNpmVersion(for: tool)
        default:
            return nil
        }
    }

    private func readNpmPackageVersion(
        tool: ProgrammingTool,
        binaryPath: String,
        resolvedBinaryPath: String?,
        installLocation: String?
    ) -> String? {
        var candidates: [String] = []

        if let installLocation {
            candidates.append(installLocation)
        }
        if let resolvedBinaryPath, let packageDir = npmPackageDirectory(from: resolvedBinaryPath, tool: tool) {
            candidates.append(packageDir)
        }
        if let packageDir = npmPackageDirectory(from: binaryPath, tool: tool) {
            candidates.append(packageDir)
        }
        if let inferred = inferNpmPackageDirectory(fromBinaryPath: binaryPath, tool: tool) {
            candidates.append(inferred)
        }

        var visited: Set<String> = []
        for candidate in candidates where visited.insert(candidate).inserted {
            guard let version = readVersionFromPackageJSON(directory: candidate) else { continue }
            return version
        }

        return nil
    }

    private func readVersionFromPackageJSON(directory: String) -> String? {
        let packageFile = URL(fileURLWithPath: directory).appendingPathComponent("package.json").path
        guard fileManager.fileExists(atPath: packageFile) else { return nil }
        guard let data = fileManager.contents(atPath: packageFile) else { return nil }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            return nil
        }

        return normalizedVersion(version)
    }

    private func normalizedVersion(_ rawVersion: String?) -> String? {
        guard
            let rawVersion,
            let firstLine = rawVersion.components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !firstLine.isEmpty
        else {
            return nil
        }

        let invalidMarkers = [
            "env:",
            "no such file or directory",
            "command not found",
            "not found",
            "permission denied",
            "failed",
            "error:",
            "warning:",
            "operation not permitted",
            "proceeding,"
        ]

        for line in rawVersion.components(separatedBy: .newlines) {
            let candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { continue }
            let cleaned = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let lowered = cleaned.lowercased()
            if invalidMarkers.contains(where: { lowered.contains($0) }) {
                continue
            }
            if cleaned.contains(where: \.isNumber) {
                return cleaned
            }
        }

        return nil
    }

    private func getNpmVersion(for tool: ProgrammingTool) -> String? {
        guard let packageName = tool.npmPackageName else { return nil }

        let output = shellCommandRunner("npm list -g \(packageName) --depth=0")

        // Parse output like: /usr/local/lib/node_modules
        // ├── @anthropic-ai/claude-code@2.1.42
        // └── @google/gemini-cli@0.28.2

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(packageName) {
                // Extract version after @
                if let atIndex = line.lastIndex(of: "@") {
                    let versionStart = line.index(after: atIndex)
                    let version = String(line[versionStart...]).trimmingCharacters(in: .whitespaces)
                    if !version.isEmpty && !version.hasPrefix("──") && !version.hasPrefix("└") {
                        return normalizedVersion(version)
                    }
                }
            }
        }
        return nil
    }

    private struct ShellExecutionResult {
        let output: String
        let status: Int32
    }

    private static func runShellCommandSync(_ command: String) -> String {
        var processLogs: [String] = ["$ \(command)"]

        var result = executeShellCommand(command, interactive: false)
        if shouldRetryWithInteractiveShell(output: result.output, status: result.status) {
            processLogs.append("检测到环境变量问题，正在使用登录 shell 重试...")
            let interactiveResult = executeShellCommand(command, interactive: true)
            if interactiveResult.status == 0 || !interactiveResult.output.isEmpty {
                result = interactiveResult
            }
        }

        if shouldRetryWithAdministratorPrivileges(
            command: command,
            output: result.output,
            status: result.status
        ) {
            processLogs.append("检测到权限不足，正在请求管理员权限...")
            let adminResult = executeShellCommandAsAdministrator(command)
            if adminResult.status == 0 || !adminResult.output.isEmpty {
                result = adminResult
            }
        }

        let trimmedOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            processLogs.append(trimmedOutput)
        }

        processLogs.append(
            result.status == 0
            ? "命令执行完成（退出码 0）"
            : "命令执行失败（退出码 \(result.status)）"
        )

        return processLogs.joined(separator: "\n")
    }

    private static func runShellCommandAsAdministratorSync(_ command: String) -> String {
        var processLogs: [String] = ["$ \(command)", "检测到需要管理员权限，正在请求授权..."]
        let result = executeShellCommandAsAdministrator(command)
        let trimmedOutput = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedOutput.isEmpty {
            processLogs.append(trimmedOutput)
        }
        processLogs.append(
            result.status == 0
            ? "命令执行完成（退出码 0）"
            : "命令执行失败（退出码 \(result.status)）"
        )
        return processLogs.joined(separator: "\n")
    }

    private static func executeShellCommand(_ command: String, interactive: Bool) -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [interactive ? "-lic" : "-lc", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return ShellExecutionResult(output: output, status: process.terminationStatus)
        } catch {
            return ShellExecutionResult(output: "", status: 1)
        }
    }

    private static func shouldRetryWithInteractiveShell(output: String, status: Int32) -> Bool {
        guard status != 0 else { return false }
        let lowered = output.lowercased()
        return lowered.contains("command not found")
            || lowered.contains("no such file or directory")
            || lowered.contains("not found")
            || lowered.contains("npm:")
    }

    private static func shouldRetryWithAdministratorPrivileges(
        command: String,
        output: String,
        status: Int32
    ) -> Bool {
        guard status != 0 else { return false }

        let loweredCommand = command.lowercased()
        let supportsPrivilegeRetry =
            loweredCommand.contains("npm install -g")
            || loweredCommand.contains("npm update -g")
            || loweredCommand.contains("npm uninstall -g")

        guard supportsPrivilegeRetry else { return false }

        let loweredOutput = output.lowercased()
        return loweredOutput.contains("eacces")
            || loweredOutput.contains("permission denied")
            || loweredOutput.contains("operation not permitted")
            || loweredOutput.contains("syscall rename")
    }

    private static func executeShellCommandAsAdministrator(_ command: String) -> ShellExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")

        let shellWrappedCommand = "/bin/zsh -lc '\(escapeSingleQuotedShell(command))'"
        let script = "do shell script \"\(escapeAppleScriptString(shellWrappedCommand))\" with administrator privileges"
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            return ShellExecutionResult(output: output, status: process.terminationStatus)
        } catch {
            return ShellExecutionResult(output: "", status: 1)
        }
    }

    private static func escapeSingleQuotedShell(_ command: String) -> String {
        command.replacingOccurrences(of: "'", with: "'\"'\"'")
    }

    private static func escapeAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    func detectInstallMethod(_ path: String) -> InstallMethod {
        let lowercased = path.lowercased()

        // Check for Homebrew
        if lowercased.contains("/opt/homebrew/") || lowercased.contains("/usr/local/homebrew/") {
            return .homebrew
        }

        // Check for npm global packages (including /usr/local/lib/node_modules)
        if lowercased.contains("/.nvm/") || lowercased.contains("/.fnm/") ||
           lowercased.contains("/npm-global/") || lowercased.contains("/node_modules/") ||
           lowercased.contains("/usr/local/lib/node_modules") {
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
                // Could be npm or homebrew, check if it's a symlink to node_modules
                return .npm
            }
        }

        return .unknown
    }

    func openConfigDirectory(for tool: ProgrammingTool) -> Bool {
        guard let targetPath = configDirectoryTargetPath(for: tool) else { return false }
        return openDirectory(targetPath)
    }

    func configDirectoryTargetPath(for tool: ProgrammingTool, configPaths: [String]? = nil) -> String? {
        let rawPaths = configPaths ?? tool.configPaths

        switch tool {
        case .codex:
            guard let primaryPath = rawPaths.first else { return nil }
            return (primaryPath as NSString).expandingTildeInPath
        default:
            let expandedPaths = rawPaths.map { ($0 as NSString).expandingTildeInPath }

            var directoryCandidates: [String] = []
            var fileCandidates: [String] = []

            for path in expandedPaths {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    directoryCandidates.append(path)
                } else {
                    fileCandidates.append(path)
                }
            }

            if let directory = directoryCandidates.first {
                return directory
            }

            if let filePath = fileCandidates.max(by: { lhs, rhs in
                lhs.components(separatedBy: "/").count < rhs.components(separatedBy: "/").count
            }) {
                return URL(fileURLWithPath: filePath).deletingLastPathComponent().path
            }

            return expandedPaths.first
        }
    }

    func openInstallDirectory(for installation: ToolInstallation) -> Bool {
        guard let path = installation.installLocation else { return false }
        return openDirectory(path)
    }

    func checkForUpdate(_ installation: ToolInstallation) async throws -> ToolUpdateCheckResult {
        guard installation.isInstalled else {
            throw ToolInstallationError.unsupportedOperation("未安装该工具，无法检查更新")
        }

        guard installation.installMethod != .direct, installation.installMethod != .unknown else {
            let message: String
            if let url = installation.tool.officialInstallURL {
                message = "该工具通常通过官网下载管理，请在官网检查更新：\(url)"
            } else {
                message = "该安装方式暂不支持自动检查更新"
            }
            return ToolUpdateCheckResult(
                state: .unknown,
                localVersion: normalizedVersion(installation.version),
                latestVersion: nil,
                message: message
            )
        }

        guard let packageName = installation.tool.packageName(for: installation.installMethod) else {
            throw ToolInstallationError.unsupportedOperation("未配置 \(installation.tool.title) 的 \(installation.installMethod.title) 包名")
        }

        let latestVersionResult = await fetchLatestVersion(
            for: installation.installMethod,
            packageName: packageName
        )
        let latestVersion = latestVersionResult.version
        let localVersion = normalizedVersion(installation.version)

        guard let latestVersion else {
            if latestVersionResult.issue == .npmCachePermission {
                return ToolUpdateCheckResult(
                    state: .unknown,
                    localVersion: localVersion,
                    latestVersion: nil,
                    message: "检测到 npm 缓存权限错误，可点击“一键修复 npm 缓存权限”自动处理后重试",
                    issue: .npmCachePermission
                )
            }
            return ToolUpdateCheckResult(
                state: .unknown,
                localVersion: localVersion,
                latestVersion: nil,
                message: "未能获取最新版本信息，请检查网络或包管理器配置"
            )
        }

        guard let localVersion else {
            return ToolUpdateCheckResult(
                state: .unknown,
                localVersion: nil,
                latestVersion: latestVersion,
                message: "已获取最新版本 \(latestVersion)，但当前版本无法识别"
            )
        }

        switch compareVersion(localVersion, latestVersion) {
        case .orderedAscending:
            return ToolUpdateCheckResult(
                state: .updateAvailable,
                localVersion: localVersion,
                latestVersion: latestVersion,
                message: "发现新版本：\(localVersion) → \(latestVersion)"
            )
        case .orderedDescending:
            return ToolUpdateCheckResult(
                state: .upToDate,
                localVersion: localVersion,
                latestVersion: latestVersion,
                message: "当前版本 \(localVersion) 已高于源仓库最新稳定版 \(latestVersion)"
            )
        case .orderedSame:
            return ToolUpdateCheckResult(
                state: .upToDate,
                localVersion: localVersion,
                latestVersion: latestVersion,
                message: "已是最新版本（\(localVersion)）"
            )
        }
    }

    func installTool(_ tool: ProgrammingTool) async throws -> String {
        try await installTool(tool, using: nil)
    }

    func installTool(_ tool: ProgrammingTool, using selectedMethod: InstallMethod?) async throws -> String {
        let method: InstallMethod

        if let selectedMethod {
            guard selectedMethod != .unknown else {
                throw ToolInstallationError.unsupportedOperation("未知安装方式不支持一键安装")
            }
            guard tool.preferredInstallMethods.contains(selectedMethod) else {
                throw ToolInstallationError.unsupportedOperation("\(tool.title) 不支持 \(selectedMethod.title) 安装")
            }
            guard isInstallMethodAvailable(selectedMethod, for: tool) else {
                throw ToolInstallationError.unsupportedOperation("\(selectedMethod.title) 不可用，请检查环境后重试")
            }
            method = selectedMethod
        } else {
            guard let resolvedMethod = resolveInstallMethod(for: tool) else {
                if let url = tool.officialInstallURL {
                    throw ToolInstallationError.unsupportedOperation("该工具请从官网安装：\(url)")
                }
                throw ToolInstallationError.unsupportedOperation("暂未配置可自动安装方式")
            }
            method = resolvedMethod
        }

        return try await installTool(tool, with: method)
    }

    private func installTool(_ tool: ProgrammingTool, with method: InstallMethod) async throws -> String {
        switch method {
        case .npm:
            guard let packageName = tool.packageName(for: .npm) else {
                throw ToolInstallationError.unsupportedOperation("未配置 npm 包名")
            }
            return await runShellCommand("npm install -g \(packageName)")
        case .homebrew:
            guard let packageName = tool.packageName(for: .homebrew) else {
                throw ToolInstallationError.unsupportedOperation("未配置 Homebrew 包名")
            }
            return await runShellCommand("brew install \(packageName)")
        case .pip:
            guard let packageName = tool.packageName(for: .pip) else {
                throw ToolInstallationError.unsupportedOperation("未配置 pip 包名")
            }
            if hasExecutable("pipx") {
                return await runShellCommand("pipx install \(packageName)")
            }
            return await runShellCommand("python3 -m pip install --user \(packageName)")
        case .direct:
            let url = tool.officialInstallURL ?? "官网"
            throw ToolInstallationError.unsupportedOperation("该工具请从官网安装：\(url)")
        case .unknown:
            throw ToolInstallationError.unsupportedOperation("无法识别可用安装方式")
        }
    }

    func updateTool(_ installation: ToolInstallation) async throws -> String {
        guard let command = installation.installMethod.updateCommand else {
            throw ToolInstallationError.unsupportedOperation("此安装方式不支持自动更新")
        }

        guard let packageName = installation.tool.packageName(for: installation.installMethod) else {
            throw ToolInstallationError.unsupportedOperation("未配置 \(installation.tool.title) 的 \(installation.installMethod.title) 包名")
        }
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

        guard let packageName = installation.tool.packageName(for: installation.installMethod) else {
            throw ToolInstallationError.unsupportedOperation("未配置 \(installation.tool.title) 的 \(installation.installMethod.title) 包名")
        }
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

    func repairNpmCachePermissions() async -> String {
        let cachePath = "\(NSHomeDirectory())/.npm"
        let escapedCachePath = ToolInstallationService.escapeSingleQuotedShell(cachePath)
        let adminCommand = """
        set -e
        CURRENT_USER="$(stat -f%Su /dev/console)"
        CURRENT_GROUP="$(id -gn "$CURRENT_USER")"
        NPM_CACHE_DIR='\(escapedCachePath)'
        mkdir -p "$NPM_CACHE_DIR"
        chown -R "$CURRENT_USER:$CURRENT_GROUP" "$NPM_CACHE_DIR"
        rm -rf "$NPM_CACHE_DIR/_cacache/tmp" "$NPM_CACHE_DIR/_locks" || true
        """

        let adminOutput = await runAdminShellCommand(adminCommand)
        guard commandSucceeded(adminOutput) else {
            return adminOutput
        }

        let verifyOutput = await runShellCommand("npm cache clean --force && npm cache verify")
        return [adminOutput, verifyOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    private func openDirectory(_ path: String) -> Bool {
        var expandedPath = path
        if path.hasPrefix("~") {
            expandedPath = (path as NSString).expandingTildeInPath
        }

        var targetPath = expandedPath
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: targetPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            targetPath = URL(fileURLWithPath: targetPath).deletingLastPathComponent().path
        }

        guard let existingDirectory = closestExistingDirectory(from: targetPath) else { return false }
        let url = URL(fileURLWithPath: existingDirectory)
        return NSWorkspace.shared.open(url)
    }

    private func closestExistingDirectory(from path: String) -> String? {
        var currentURL = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false

        while true {
            let currentPath = currentURL.path
            if fileManager.fileExists(atPath: currentPath, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? currentPath : currentURL.deletingLastPathComponent().path
            }

            let parentURL = currentURL.deletingLastPathComponent()
            if parentURL.path == currentURL.path {
                break
            }
            currentURL = parentURL
        }

        return nil
    }

    func preferredConfigPath(from paths: [String]) -> String? {
        var firstCandidate: String?
        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            if firstCandidate == nil {
                firstCandidate = expanded
            }
            if fileManager.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return firstCandidate
    }

    private func runShellCommand(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            continuation.resume(returning: shellCommandRunner(command))
        }
    }

    private func runAdminShellCommand(_ command: String) async -> String {
        await withCheckedContinuation { continuation in
            continuation.resume(returning: adminShellCommandRunner(command))
        }
    }

    private func commandSucceeded(_ output: String) -> Bool {
        output.localizedStandardContains("命令执行完成（退出码 0）")
    }

    private func fetchLatestVersion(
        for method: InstallMethod,
        packageName: String
    ) async -> LatestVersionFetchResult {
        let output: String

        switch method {
        case .npm:
            output = await runShellCommand("npm view \(packageName) version --json")
            return LatestVersionFetchResult(
                version: parseNpmLatestVersion(output),
                issue: detectNpmCachePermissionIssue(output: output)
            )
        case .homebrew:
            output = await runShellCommand("brew info --json=v2 \(packageName)")
            return LatestVersionFetchResult(version: parseHomebrewLatestVersion(output), issue: nil)
        case .pip:
            output = await runShellCommand("python3 -m pip index versions \(packageName)")
            return LatestVersionFetchResult(version: parsePipLatestVersion(output), issue: nil)
        default:
            return LatestVersionFetchResult(version: nil, issue: nil)
        }
    }

    private struct LatestVersionFetchResult {
        let version: String?
        let issue: ToolUpdateIssue?
    }

    private func detectNpmCachePermissionIssue(output: String) -> ToolUpdateIssue? {
        let lowered = output.lowercased()
        let hasNpmError = lowered.contains("npm error")
        let hasNpmErrorPath = lowered.contains("npm error path")
        let hasCachePath = lowered.contains("/.npm/_cacache/") || lowered.contains(".npm/_cacache")
        let hasPermissionError =
            lowered.contains("eacces")
            || lowered.contains("permission denied")
            || lowered.contains("operation not permitted")
            || lowered.contains("errno eexist")
            || lowered.contains("code eexist")
            || lowered.contains("file exists")
            || lowered.contains("syscall mkdir")
            || lowered.contains("invalid response body while trying to fetch")

        if hasNpmErrorPath && hasCachePath {
            return .npmCachePermission
        }

        if hasNpmError && hasCachePath && hasPermissionError {
            return .npmCachePermission
        }

        return nil
    }

    private func resolveInstallMethod(for tool: ProgrammingTool) -> InstallMethod? {
        for method in tool.preferredInstallMethods {
            if isInstallMethodAvailable(method, for: tool) {
                return method
            }
        }
        return nil
    }

    private func isInstallMethodAvailable(_ method: InstallMethod, for tool: ProgrammingTool) -> Bool {
        switch method {
        case .npm:
            return hasExecutable("npm") && tool.packageName(for: .npm) != nil
        case .homebrew:
            return hasExecutable("brew") && tool.packageName(for: .homebrew) != nil
        case .pip:
            return hasExecutable("python3") && tool.packageName(for: .pip) != nil
        case .direct:
            return tool.officialInstallURL != nil
        case .unknown:
            return false
        }
    }

    private func hasExecutable(_ executable: String) -> Bool {
        let output = shellCommandRunner("command -v \(executable) >/dev/null 2>&1 && echo ok")
        return output.localizedStandardContains("ok")
    }

    private func parseNpmLatestVersion(_ output: String) -> String? {
        guard !output.isEmpty else { return nil }

        if let jsonValue = decodedJSONValue(from: output) {
            if let version = jsonValue as? String {
                return parseStrictVersionToken(version)
            }
            if let versions = jsonValue as? [String] {
                return versions.compactMap(parseStrictVersionToken).first
            }
            return nil
        }

        for line in output.components(separatedBy: .newlines) {
            if let version = parseStrictVersionToken(line) {
                return version
            }
        }

        return nil
    }

    private func parseHomebrewLatestVersion(_ output: String) -> String? {
        guard
            let object = decodedJSONValue(from: output) as? [String: Any],
            let formulae = object["formulae"] as? [[String: Any]],
            let first = formulae.first
        else {
            return nil
        }

        if let versions = first["versions"] as? [String: Any],
           let stable = versions["stable"] as? String
        {
            return parseStrictVersionToken(stable)
        }

        return nil
    }

    private func parsePipLatestVersion(_ output: String) -> String? {
        guard !output.isEmpty else { return nil }
        let lines = output.components(separatedBy: .newlines)

        if let firstLine = lines.first(where: { $0.localizedCaseInsensitiveContains("latest:") }),
           let value = valueAfterColon(from: firstLine)
        {
            return normalizedVersion(value)
        }

        if let versionsLine = lines.first(where: { $0.localizedCaseInsensitiveContains("available versions:") }),
           let value = valueAfterColon(from: versionsLine)
        {
            let versions = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return versions.compactMap { normalizedVersion($0) }.first
        }

        return nil
    }

    private func decodedJSONValue(from output: String) -> Any? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = jsonValue(from: trimmed) {
            return value
        }

        if let candidate = extractJSONSlice(from: output, open: "{", close: "}"),
           let value = jsonValue(from: candidate)
        {
            return value
        }

        if let candidate = extractJSONSlice(from: output, open: "[", close: "]"),
           let value = jsonValue(from: candidate)
        {
            return value
        }

        return nil
    }

    private func extractJSONSlice(from text: String, open: Character, close: Character) -> String? {
        guard
            let start = text.firstIndex(of: open),
            let end = text.lastIndex(of: close),
            start <= end
        else {
            return nil
        }
        return String(text[start...end])
    }

    private func jsonValue(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func parseStrictVersionToken(_ raw: String) -> String? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"',"))

        guard !cleaned.isEmpty else { return nil }
        let pattern = #"^v?\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?$"#
        guard cleaned.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return normalizedVersion(cleaned)
    }

    private func valueAfterColon(from line: String) -> String? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedSegments(from: lhs)
        let right = normalizedSegments(from: rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }

        return .orderedSame
    }

    private func normalizedSegments(from version: String) -> [Int] {
        let cleaned = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = cleaned.hasPrefix("v") ? String(cleaned.dropFirst()) : cleaned
        let head = withoutPrefix.split(separator: "-").first.map(String.init) ?? withoutPrefix
        return head
            .split(separator: ".")
            .map { token in
                let digits = token.filter(\.isNumber)
                return Int(digits) ?? 0
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
