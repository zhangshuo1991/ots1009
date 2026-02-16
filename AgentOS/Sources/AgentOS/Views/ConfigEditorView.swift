import SwiftUI

struct ConfigEditorView: View {
    let tool: ProgrammingTool
    @Binding var isPresented: Bool
    @State private var config = ToolConfig()
    @State private var selectedConfigPath: String = ""
    @State private var isSaving = false
    @State private var statusMessage = ""

    private let configService = ConfigEditorService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("\(tool.title) - 设置")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // API Key
            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.subheadline.weight(.medium))
                SecureField("输入 API Key", text: $config.apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            // HTTP Proxy
            VStack(alignment: .leading, spacing: 4) {
                Text("HTTP 代理")
                    .font(.subheadline.weight(.medium))
                TextField("http://127.0.0.1:7890", text: $config.httpProxy)
                    .textFieldStyle(.roundedBorder)
            }

            // HTTPS Proxy
            VStack(alignment: .leading, spacing: 4) {
                Text("HTTPS 代理")
                    .font(.subheadline.weight(.medium))
                TextField("http://127.0.0.1:7890", text: $config.httpsProxy)
                    .textFieldStyle(.roundedBorder)
            }

            // Model
            VStack(alignment: .leading, spacing: 4) {
                Text("默认模型")
                    .font(.subheadline.weight(.medium))
                TextField("例如: claude-sonnet-4-5", text: $config.model)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            // Config files
            VStack(alignment: .leading, spacing: 8) {
                Text("配置文件")
                    .font(.subheadline.weight(.medium))

                ForEach(tool.configPaths, id: \.self) { path in
                    HStack {
                        Text(path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("编辑") {
                            _ = configService.openConfigFile(path)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusMessage.contains("成功") ? .green : .red)
            }

            // Actions
            HStack {
                Spacer()
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)

                Button("保存") {
                    Task {
                        await saveConfig()
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onAppear {
            loadConfig()
        }
    }

    private func loadConfig() {
        if let path = configService.findExistingConfigPath(for: tool) {
            selectedConfigPath = path
            Task {
                if let loaded = await configService.loadConfig(from: path) {
                    config = loaded
                }
            }
        } else if let firstPath = tool.configPaths.first {
            selectedConfigPath = firstPath
        }
    }

    private func saveConfig() async {
        isSaving = true
        statusMessage = ""

        do {
            try await configService.saveConfig(config, to: selectedConfigPath)
            statusMessage = "保存成功"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isPresented = false
            }
        } catch {
            statusMessage = "保存失败: \(error.localizedDescription)"
        }

        isSaving = false
    }
}
