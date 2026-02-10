import SwiftUI
import GhosttyKit

/// The main workspace view using NavigationSplitView.
/// Sidebar shows repos/worktrees; detail shows the terminal.
struct WorkspaceView<ViewModel: TerminalViewModel>: View {
    @ObservedObject var ghostty: Ghostty.App
    @ObservedObject var viewModel: ViewModel
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sidebarState: WorkspaceSidebarState
    weak var delegate: (any TerminalViewDelegate)?

    let onSelectWorktree: (WorkspaceStore.Worktree) -> Void
    let onResumeSession: (WorkspaceStore.Worktree) -> Void
    let onAddTerminal: (WorkspaceStore.Worktree) -> Void

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarState.columnVisibility) {
            WorkspaceSidebarView(
                store: store,
                sidebarState: sidebarState,
                onSelectWorktree: onSelectWorktree,
                onResumeSession: onResumeSession,
                onAddTerminal: onAddTerminal
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            if sidebarState.hasActiveWorktree {
                TerminalView(
                    ghostty: ghostty,
                    viewModel: viewModel,
                    delegate: delegate
                )
            } else {
                EmptyWorkspaceView()
            }
        }
    }
}

/// Placeholder shown when no worktree is selected.
struct EmptyWorkspaceView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Add a repository to get started")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Use the sidebar to add a git repository\nand navigate between worktrees.")
                .font(.body)
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .greatestFiniteMagnitude, maxHeight: .greatestFiniteMagnitude)
    }
}
