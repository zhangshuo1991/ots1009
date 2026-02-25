import Foundation

enum CLITerminalRunnerFactory {
    static func makeDefaultRunner() -> any CLITerminalRunning {
        CLIGhosttyTerminalRunner()
    }
}
