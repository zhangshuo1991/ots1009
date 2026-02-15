import Observation
import SwiftUI

struct CollaborationPanelView: View {
    @Bindable var viewModel: DashboardViewModel
    let task: WorkTask

    @State private var newComment: String = ""
    @State private var role: CollaborationRole = .owner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("协作与看板")
                    .font(.headline)
                Spacer()
                Picker("看板列", selection: Binding(
                    get: { task.lane },
                    set: { viewModel.setTaskLane(taskID: task.id, lane: $0) }
                )) {
                    ForEach(BoardLane.allCases) { lane in
                        Text(lane.title).tag(lane)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("仓库上下文")
                        .font(.subheadline.weight(.semibold))
                    Text(task.repositoryPath.isEmpty ? "未设置仓库路径" : task.repositoryPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("分支：\(task.branchName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 8) {
                    Text("当前看板列")
                        .font(.subheadline.weight(.semibold))
                    Text(task.lane.title)
                        .font(.headline)
                    Text("用于本地多人协作视角切换（待办/执行/评审/完成）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(task.lane.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("协作评论")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Picker("角色", selection: $role) {
                        ForEach(CollaborationRole.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    TextField("输入评论内容（如：请先过 lint，再发起评审）", text: $newComment)
                        .textFieldStyle(.roundedBorder)
                    Button("发送") {
                        withAnimation(.snappy(duration: 0.2)) {
                            viewModel.addComment(taskID: task.id, author: role, content: newComment)
                            newComment = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if task.comments.isEmpty {
                Text("暂无评论")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(task.comments.reversed().prefix(20))) { comment in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(comment.author.tintColor)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(comment.author.title)
                                            .font(.caption.weight(.semibold))
                                        Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(comment.content)
                                        .font(.caption)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 240)
            }
        }
        .cardSurface()
    }
}
