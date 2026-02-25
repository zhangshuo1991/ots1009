import SwiftUI

struct ToolSidebarRowView: View {
    let installation: ToolInstallation
    let isSelected: Bool
    let onSelect: () -> Void
    var isBatchMode: Bool = false
    var isBatchSelected: Bool = false
    var onBatchToggle: (() -> Void)? = nil

    var body: some View {
        Button(action: isBatchMode ? (onBatchToggle ?? {}) : onSelect) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DesignTokens.ColorToken.rowSelectedBackground)

                if isSelected && !isBatchMode {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(DesignTokens.ColorToken.brandPrimary)
                        .frame(width: 2)
                        .padding(.vertical, 5)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        if isBatchMode {
                            batchCheckbox
                        }

                        statusIcon

                        VStack(alignment: .leading, spacing: 3) {
                            Text(installation.tool.title)
                                .font(.system(size: 13, weight: isHighlighted ? .bold : .medium))
                                .foregroundStyle(
                                    isHighlighted
                                    ? DesignTokens.ColorToken.textPrimary
                                    : DesignTokens.ColorToken.textSecondary
                                )
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Text(installation.isInstalled ? "已安装" : "未安装")
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        (installation.isInstalled
                                        ? DesignTokens.ColorToken.statusSuccess
                                        : DesignTokens.ColorToken.statusWarning).opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(
                                        installation.isInstalled
                                        ? DesignTokens.ColorToken.statusSuccess
                                        : DesignTokens.ColorToken.statusWarning
                                    )

                                if installation.isInstalled {
                                    Text(installation.installMethod.title)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(DesignTokens.ColorToken.textMuted)
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        if !isBatchMode {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(
                                    isHighlighted
                                    ? DesignTokens.ColorToken.textSecondary
                                    : DesignTokens.ColorToken.textMuted
                                )
                        }
                    }

                    if isHighlighted {
                        Text(secondaryHint)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(DesignTokens.ColorToken.inputBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(DesignTokens.ColorToken.borderDefault, lineWidth: 1)
                            )
                    } else {
                        Text(secondaryHint)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(DesignTokens.ColorToken.textMuted)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, isHighlighted ? 9 : 8)
                .padding(.trailing, 8)
                .padding(.vertical, 7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(
                        isBatchMode && isBatchSelected
                        ? DesignTokens.ColorToken.brandPrimary.opacity(0.3)
                        : (isSelected && !isBatchMode
                            ? DesignTokens.ColorToken.rowSelectedBorder
                            : Color.clear),
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isBatchMode && isBatchSelected
                        ? DesignTokens.ColorToken.brandPrimary.opacity(0.06)
                        : (isSelected && !isBatchMode
                            ? DesignTokens.ColorToken.rowSelectedBackground
                            : Color.clear)
                    )
            )
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel("\(installation.tool.title)，\(installation.isInstalled ? "已安装" : "未安装")\(isBatchMode && isBatchSelected ? "，已选中" : "")")
        .accessibilityHint(isBatchMode ? "切换批量选中状态" : "显示该工具详情")
    }

    private var statusIcon: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                (installation.isInstalled
                ? DesignTokens.ColorToken.statusSuccess
                : DesignTokens.ColorToken.statusWarning).opacity(0.12)
            )
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: installation.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        installation.isInstalled
                        ? DesignTokens.ColorToken.statusSuccess
                        : DesignTokens.ColorToken.statusWarning
                    )
            }
    }

    private var isHighlighted: Bool {
        isBatchMode ? isBatchSelected : isSelected
    }

    private var batchCheckbox: some View {
        Image(systemName: isBatchSelected ? "checkmark.square.fill" : "square")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(
                isBatchSelected
                ? DesignTokens.ColorToken.brandPrimary
                : DesignTokens.ColorToken.textMuted
            )
            .frame(width: 20, height: 20)
    }

    private var secondaryHint: String {
        if let version = installation.version, !version.isEmpty {
            return version
        }

        if let binaryPath = installation.binaryPath, !binaryPath.isEmpty {
            return binaryPath
        }

        return installation.isInstalled ? "已安装，等待版本检测" : installation.tool.installHint
    }
}
