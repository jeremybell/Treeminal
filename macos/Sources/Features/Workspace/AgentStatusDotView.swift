import Combine
import SwiftUI

/// A small colored dot indicating Claude agent status for a worktree.
struct AgentStatusDotView: View {
    let status: WorktreeAgentStatus?

    private let dotSize: CGFloat = 6

    var body: some View {
        if let status {
            Circle()
                .fill(color(for: status))
                .frame(width: dotSize, height: dotSize)
                .modifier(PulseModifier(shouldPulse: shouldPulse(status)))
        }
    }

    private func color(for status: WorktreeAgentStatus) -> Color {
        switch status {
        case .working: return .orange
        case .permission: return .red
        case .review: return .green
        }
    }

    private func shouldPulse(_ status: WorktreeAgentStatus) -> Bool {
        switch status {
        case .working, .permission: return true
        case .review: return false
        }
    }
}

/// Applies a pulsing scale animation when active.
private struct PulseModifier: ViewModifier {
    let shouldPulse: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing && shouldPulse ? 1.4 : 1.0)
            .opacity(isPulsing && shouldPulse ? 0.6 : 1.0)
            .animation(
                shouldPulse
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear {
                if shouldPulse {
                    isPulsing = true
                }
            }
            .onReceive(Just(shouldPulse)) { newValue in
                isPulsing = newValue
            }
    }
}
