import SwiftUI

/// Represents a selection in the workspace sidebar.
enum WorkspaceSidebarSelection: Hashable {
    case repo(id: UUID)
    case worktree(repoID: UUID, path: String)
}

/// Sort order for worktrees in the sidebar.
enum WorktreeSortOrder: String, CaseIterable {
    case alphabetical
    case recentActivity

    var label: String {
        switch self {
        case .alphabetical: return "Alphabetical"
        case .recentActivity: return "Recent Activity"
        }
    }
}

/// Observable state for the workspace sidebar.
final class WorkspaceSidebarState: ObservableObject {
    @Published var columnVisibility: NavigationSplitViewVisibility = .all
    @Published var expandedRepoIDs: Set<UUID> = []
    @Published var selection: WorkspaceSidebarSelection? = nil
    @Published var hasActiveWorktree: Bool = false
    @Published var sortOrder: WorktreeSortOrder = .recentActivity
}
