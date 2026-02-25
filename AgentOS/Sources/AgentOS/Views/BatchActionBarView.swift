import SwiftUI

struct BatchActionBarView: View {
    let selectedCount: Int
    let installedSelectedCount: Int
    let hasUpdatingTools: Bool
    let hasCheckingTools: Bool
    let onCheckUpdatesAll: () -> Void
    let onUpdateAll: () -> Void
    let onUninstallAll: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("已选 \(selectedCount) 个工具")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorToken.textPrimary)

                Spacer(minLength: 0)

                Button(action: onDeselectAll) {
                    Text("取消选择")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignTokens.ColorToken.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if installedSelectedCount == 0 {
                Text("所选工具均未安装，无法执行批量操作")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorToken.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    Button(action: onCheckUpdatesAll) {
                        Text("检查更新")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.brandPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(DesignTokens.ColorToken.brandPrimary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(DesignTokens.ColorToken.brandPrimary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(hasCheckingTools)
                    .opacity(hasCheckingTools ? 0.5 : 1)

                    Button(action: onUpdateAll) {
                        Text("全部更新")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.textInverse)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(DesignTokens.ColorToken.brandPrimary)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(hasUpdatingTools)
                    .opacity(hasUpdatingTools ? 0.5 : 1)

                    Button(action: onUninstallAll) {
                        Text("全部卸载")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorToken.statusDanger)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(DesignTokens.ColorToken.statusDanger.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(DesignTokens.ColorToken.statusDanger.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DesignTokens.ColorToken.panelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignTokens.ColorToken.borderDefault)
                .frame(height: 1)
        }
    }
}
