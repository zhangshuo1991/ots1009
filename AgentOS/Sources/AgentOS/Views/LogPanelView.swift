import SwiftUI

struct LogPanelView: View {
    let logText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("统一日志")
                .font(.headline)

            ScrollView {
                Text(logText.isEmpty ? "暂无日志输出" : logText)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.black.opacity(0.88), in: .rect(cornerRadius: 10))
                    .foregroundStyle(Color.green.opacity(0.95))
            }
            .frame(minHeight: 220)
        }
        .cardSurface()
    }
}
