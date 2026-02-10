import SwiftUI

/// A sheet view showing all Claude Code sessions for a worktree,
/// allowing the user to pick one to resume.
struct SessionPickerView: View {
    let sessions: [ClaudeSession]
    let onSelect: (ClaudeSession) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Resume Session")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if sessions.isEmpty {
                Text("No previous sessions found.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                List(sessions) { session in
                    SessionRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(session) }
                }
                .listStyle(.inset)
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
    }
}

/// A single session row in the session picker.
private struct SessionRow: View {
    let session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.snippet ?? "New session")
                .font(.body)
                .lineLimit(1)

            HStack(spacing: 8) {
                Label(
                    "\(session.messageCount) message\(session.messageCount == 1 ? "" : "s")",
                    systemImage: "bubble.left"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                Text(relativeTimestamp(session.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
