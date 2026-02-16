import Observation
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var state: AppState

    @State private var draftWorkspacePath: String = ""
    @State private var draftOutput: String = ""
    @State private var importFolderPresented = false

    var body: some View {
        VStack(spacing: 14) {
            topBar
            detectionPanel

            HStack(alignment: .top, spacing: 12) {
                sessionCanvas

                if state.showingInspector {
                    inspectorPanel
                        .frame(width: 320)
                }
            }

            bottomBar
        }
        .padding(16)
        .frame(minWidth: 1180, minHeight: 760)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .fileImporter(
            isPresented: $importFolderPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let first = urls.first {
                draftWorkspacePath = first.path
                state.saveWorkspace(path: first.path)
            }
        }
        .onAppear {
            draftWorkspacePath = state.workspacePath
        }
        .sheet(isPresented: $state.showingConfigEditor) {
            if let tool = state.selectedToolForConfig {
                ConfigEditorView(
                    tool: tool,
                    isPresented: $state.showingConfigEditor
                )
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("Agent OS")
                .font(.system(size: 26, weight: .bold, design: .rounded))

            Spacer()

            TextField("选择项目目录", text: $draftWorkspacePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: 360)

            Button("选择文件夹") {
                importFolderPresented = true
            }
            .buttonStyle(.bordered)

            Button("保存目录") {
                state.saveWorkspace(path: draftWorkspacePath)
            }
            .buttonStyle(.borderedProminent)

            Picker("Agent", selection: $state.selectedAgent) {
                ForEach(AgentKind.allCases) { agent in
                    Text(agent.title).tag(agent)
                }
            }
            .frame(width: 170)

            Picker("模型", selection: $state.selectedModel) {
                ForEach(state.selectedAgent.models, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .frame(width: 230)

            Picker("模式", selection: $state.runMode) {
                ForEach(RunMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Button {
                state.showingInspector.toggle()
            } label: {
                Image(systemName: state.showingInspector ? "sidebar.right" : "sidebar.right")
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var detectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("编程工具安装检测")
                    .font(.headline)
                Spacer()
                if let updatedAt = state.detectionUpdatedAt {
                    Text(updatedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("刷新检测") {
                    state.refreshDetections()
                    state.refreshInstallations()
                }
                .buttonStyle(.borderedProminent)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(state.installations) { installation in
                    ToolCardView(
                        installation: installation,
                        onSettingsTap: {
                            state.selectedToolForConfig = installation.tool
                            state.showingConfigEditor = true
                        },
                        onOpenConfigDir: {
                            state.openConfigDirectory(for: installation.tool)
                        },
                        onOpenInstallDir: {
                            state.openInstallDirectory(for: installation.tool)
                        },
                        onUpdate: {
                            state.updateTool(installation.tool)
                        },
                        onUninstall: {
                            state.uninstallTool(installation.tool)
                        }
                    )
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var sessionCanvas: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.sessionTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text(state.objective)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(state.step.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.2), in: Capsule())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.events) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.actor)
                                .font(.caption.weight(.semibold))
                                .frame(width: 90, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.message)
                                    .font(.subheadline)
                                Text(event.time, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.white.opacity(0.88), in: .rect(cornerRadius: 10))
                    }
                }
            }
            .frame(maxHeight: .infinity)

            TextField("模拟追加输出", text: $draftOutput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    state.appendOutput(draftOutput)
                    draftOutput = ""
                }
        }
        .padding(14)
        .background(Color.white.opacity(0.92), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var inspectorPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("终端日志")
                .font(.headline)
            ScrollView {
                Text(state.liveOutput.isEmpty ? "暂无输出" : state.liveOutput)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.black.opacity(0.9), in: .rect(cornerRadius: 10))
            .foregroundStyle(.white)

            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                state.start()
            } label: {
                Label("启动", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                state.pause()
            } label: {
                Label("暂停", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                state.resume()
            } label: {
                Label("继续", systemImage: "playpause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button("提交审批") {
                state.requestReview()
            }
            .buttonStyle(.bordered)

            Button("批准") {
                state.approve()
            }
            .buttonStyle(.borderedProminent)

            Button("拒绝") {
                state.reject()
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .padding(10)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}
