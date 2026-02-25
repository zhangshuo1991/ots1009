import SwiftUI

struct ConfigEditorView: View {
    let tool: ProgrammingTool
    @Environment(\.dismiss) private var dismiss
    @State private var config = ToolEditableConfig.empty
    @State private var isSaving = false
    @State private var statusMessage = ""

    private let configService = ConfigEditorService()
    private var detailProfile: ToolDetailProfile { tool.detailProfile }
    private var editableFields: [ToolEditableFieldDescriptor] { tool.supportedEditableFields }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            editorContent

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("成功") ? .green : .red)
            }

            footerActions
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            loadConfig()
        }
    }

    private var header: some View {
        HStack {
            Text("\(tool.title) - 配置")
                .font(.headline)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(detailProfile.roleSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if editableFields.isEmpty {
                Label("该工具不支持在本应用直接编辑参数。", systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(editableFields) { field in
                    VStack(alignment: .leading, spacing: 6) {
                        fieldTitle(field.label)
                        if field.isSecure {
                            SecureField(field.placeholder, text: binding(for: field.id))
                                .textFieldStyle(.roundedBorder)
                        } else {
                            TextField(field.placeholder, text: binding(for: field.id))
                                .textFieldStyle(.roundedBorder)
                        }
                        if !field.helper.isEmpty {
                            Text(field.helper)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                let editablePaths = configService.editableConfigPaths(for: tool)
                if !editablePaths.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("将写入以下配置文件")
                            .font(.subheadline.weight(.medium))

                        ForEach(editablePaths, id: \.self) { path in
                            HStack {
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("打开") {
                                    _ = configService.openConfigFile(path)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        HStack {
            Spacer()
            Button("取消") {
                dismiss()
            }
            .keyboardShortcut(.escape)

            Button("保存") {
                saveConfig()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || editableFields.isEmpty)
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
    }

    private func binding(for fieldID: String) -> Binding<String> {
        Binding(
            get: { config.value(for: fieldID) },
            set: { newValue in
                config.setValue(newValue, for: fieldID)
            }
        )
    }

    private func loadConfig() {
        guard !editableFields.isEmpty else {
            config = .empty
            return
        }
        if let loaded = configService.loadEditableConfigSync(for: tool) {
            config = loaded
        }
    }

    private func saveConfig() {
        guard !editableFields.isEmpty else {
            statusMessage = "该工具不支持在本应用内保存配置。"
            return
        }
        isSaving = true
        statusMessage = ""

        do {
            try configService.saveEditableConfig(config, for: tool)
            statusMessage = "保存成功"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                dismiss()
            }
        } catch {
            statusMessage = "保存失败: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
