import SwiftUI

/// A popover view showing all Claude Code sessions for a worktree,
/// allowing the user to pick one to resume.
struct SessionPickerView: View {
    let sessions: [ClaudeSession]
    let onSelect: (ClaudeSession) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resume Session")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            Divider()

            if sessions.isEmpty {
                Text("No previous sessions found.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sessions) { session in
                            SessionRow(session: session) {
                                onSelect(session)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(maxHeight: 300)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 320)
    }
}

/// A single session row in the session picker.
private struct SessionRow: View {
    let session: ClaudeSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.snippet ?? "New session")
                    .font(.body)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Label(
                        "\(session.messageCount) message\(session.messageCount == 1 ? "" : "s")",
                        systemImage: "bubble.left"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text(relativeTimestamp(session.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.001)) // Invisible but tappable
        )
    }

    private func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
