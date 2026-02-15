import SwiftUI

struct PhaseTimelineView: View {
    let phase: TaskPhase
    let history: [TaskPhase]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TaskPhase.allCases, id: \.self) { item in
                VStack(spacing: 8) {
                    Circle()
                        .fill(color(for: item))
                        .frame(width: 14, height: 14)
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(item == phase ? .primary : .secondary)
                }
                if item != TaskPhase.allCases.last {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 1)
                }
            }
        }
        .padding(12)
        .cardSurface()
    }

    private func color(for item: TaskPhase) -> Color {
        if item == phase {
            return .blue
        }
        if history.contains(item) {
            return .green
        }
        return .gray.opacity(0.4)
    }
}
