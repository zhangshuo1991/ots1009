import SwiftUI

enum DesignTokens {
    enum ColorToken {
        // Brand (from code.html)
        static let brandPrimary = Color(hex: 0x007BFF)
        static let brandPrimaryHover = Color(hex: 0x0069D9)
        static let brandAccent = Color(hex: 0x0EA5E9)

        // Background
        static let appBackground = Color(hex: 0xFFFFFF)
        static let sidebarBackground = Color(hex: 0xF8F9FA)
        static let panelBackground = Color(hex: 0xFFFFFF)
        static let sectionBackground = Color(hex: 0xFFFFFF)
        static let inputBackground = Color(hex: 0xF9FAFB)
        static let hoverBackground = Color(hex: 0xF9FAFB)

        // Text
        static let textPrimary = Color(hex: 0x1F2937)
        static let textSecondary = Color(hex: 0x4B5563)
        static let textMuted = Color(hex: 0x9CA3AF)
        static let textInverse = Color(hex: 0xFFFFFF)

        // Border
        static let borderDefault = Color(hex: 0xF1F3F5)
        static let borderStrong = Color(hex: 0xE5E7EB)
        static let borderFocus = Color(hex: 0x007BFF)

        // Status
        static let statusSuccess = Color(hex: 0x22C55E)
        static let statusWarning = Color(hex: 0xF59E0B)
        static let statusDanger = Color(hex: 0xEF4444)
        static let statusInfo = Color(hex: 0x007BFF)

        // Sidebar row
        static let rowSelectedBackground = Color(hex: 0xFFFFFF)
        static let rowSelectedBorder = Color(hex: 0xBFDBFE)
        static let rowHoverBackground = Color(hex: 0xFFFFFF)

        // Unified terminal workspace
        static let terminalCanvas = Color(hex: 0x0E1117)
        static let terminalHeader = Color(hex: 0x121823)
        static let terminalSurface = Color(hex: 0x161E2B)
        static let terminalElevated = Color(hex: 0x1A2433)
        static let terminalDivider = Color(hex: 0x283449)
        static let terminalTextPrimary = Color(hex: 0xD9E2F0)
        static let terminalTextSecondary = Color(hex: 0xAAB7C9)
        static let terminalTextMuted = Color(hex: 0x7A879C)
        static let terminalAccent = Color(hex: 0x4C8DFF)
        static let terminalDanger = Color(hex: 0xE96060)
    }
}

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
