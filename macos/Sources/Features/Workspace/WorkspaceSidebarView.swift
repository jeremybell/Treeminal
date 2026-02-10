import SwiftUI
import UniformTypeIdentifiers

/// The sidebar view for the workspace, showing repos and their worktrees.
struct WorkspaceSidebarView: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var sidebarState: WorkspaceSidebarState
    let onSelectWorktree: (WorkspaceStore.Worktree) -> Void
    let onResumeSession: (WorkspaceStore.Worktree) -> Void
    let onAddTerminal: (WorkspaceStore.Worktree) -> Void

    @State private var showingCreateWorktreeSheet = false
    @State private var createWorktreeRepoID: UUID?
    @State private var showingAddRepoPanel = false

    // Confirmation state
    @State private var confirmRemoveRepo: WorkspaceStore.Repository?
    @State private var confirmRemoveWorktree: (repoID: UUID, path: String)?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $sidebarState.selection) {
                ForEach(store.repositories) { repo in
                    DisclosureGroup(
                        isExpanded: expandedBinding(for: repo.id)
                    ) {
                        // Worktree rows
                        let worktrees = sortedWorktrees(for: repo)
                        ForEach(worktrees) { worktree in
                            WorktreeRow(
                                worktree: worktree,
                                agentStatus: store.agentStatusByWorktreePath[worktree.path]?.status,
                                isSelected: isSelected(worktree),
                                onSelect: { onSelectWorktree(worktree) }
                            )
                            .tag(WorkspaceSidebarSelection.worktree(repoID: repo.id, path: worktree.path))
                            .contextMenu {
                                Button("Resume Session") {
                                    onResumeSession(worktree)
                                }
                                Button("Add Terminal") {
                                    onAddTerminal(worktree)
                                }
                                Divider()
                                Button("Remove Worktree...") {
                                    confirmRemoveWorktree = (repoID: repo.id, path: worktree.path)
                                }
                                .disabled(worktree.isMain)
                                .help(worktree.isMain ? "The main worktree cannot be removed" : "")
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill.badge.gearshape")
                                .foregroundColor(.secondary)
                            Text(repo.name)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                createWorktreeRepoID = repo.id
                                showingCreateWorktreeSheet = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Create worktree")
                        }
                        .contextMenu {
                            Button("Remove Repository...") {
                                confirmRemoveRepo = repo
                            }
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: repo.path)
                            }
                            Divider()
                            Button("Refresh") {
                                store.refreshAll()
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Bottom bar
            HStack {
                Button {
                    showingAddRepoPanel = true
                } label: {
                    Label("Add Repo...", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Spacer()

                Menu {
                    ForEach(WorktreeSortOrder.allCases, id: \.self) { order in
                        Button {
                            sidebarState.sortOrder = order
                        } label: {
                            if sidebarState.sortOrder == order {
                                Label(order.label, systemImage: "checkmark")
                            } else {
                                Text(order.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .help("Sort worktrees")
            }
        }
        .fileImporter(
            isPresented: $showingAddRepoPanel,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            store.addRepository(path: url.path)
            // Auto-expand newly added repo
            if let repo = store.repositories.last {
                sidebarState.expandedRepoIDs.insert(repo.id)
            }
        }
        .sheet(isPresented: $showingCreateWorktreeSheet) {
            if let repoID = createWorktreeRepoID {
                CreateWorktreeSheet(store: store, repoID: repoID, isPresented: $showingCreateWorktreeSheet)
            }
        }
        .alert(
            "Remove Repository?",
            isPresented: Binding(
                get: { confirmRemoveRepo != nil },
                set: { if !$0 { confirmRemoveRepo = nil } }
            ),
            presenting: confirmRemoveRepo
        ) { repo in
            Button("Remove", role: .destructive) {
                store.removeRepository(id: repo.id)
                confirmRemoveRepo = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveRepo = nil
            }
        } message: { repo in
            Text("Remove \"\(repo.name)\" from the sidebar? This does not delete the repository from disk.")
        }
        .alert(
            "Remove Worktree?",
            isPresented: Binding(
                get: { confirmRemoveWorktree != nil },
                set: { if !$0 { confirmRemoveWorktree = nil } }
            )
        ) {
            Button("Remove", role: .destructive) {
                if let info = confirmRemoveWorktree {
                    store.removeWorktree(repoID: info.repoID, path: info.path)
                }
                confirmRemoveWorktree = nil
            }
            Button("Cancel", role: .cancel) {
                confirmRemoveWorktree = nil
            }
        } message: {
            if let info = confirmRemoveWorktree {
                Text("Remove the worktree at \"\(info.path)\"? This will delete the worktree directory.")
            }
        }
    }

    // MARK: - Helpers

    private func expandedBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { sidebarState.expandedRepoIDs.contains(id) },
            set: { expanded in
                if expanded {
                    sidebarState.expandedRepoIDs.insert(id)
                } else {
                    sidebarState.expandedRepoIDs.remove(id)
                }
            }
        )
    }

    private func sortedWorktrees(for repo: WorkspaceStore.Repository) -> [WorkspaceStore.Worktree] {
        let worktrees = store.worktreesByRepoID[repo.id] ?? []
        switch sidebarState.sortOrder {
        case .alphabetical:
            return worktrees.sorted { a, b in
                // Main worktree always first
                if a.isMain { return true }
                if b.isMain { return false }
                return a.branch.localizedStandardCompare(b.branch) == .orderedAscending
            }
        case .recentActivity:
            return worktrees.sorted { a, b in
                // Main worktree always first
                if a.isMain { return true }
                if b.isMain { return false }
                let aTime = ClaudeSessionScanner.latestSession(for: a.path)?.timestamp ?? .distantPast
                let bTime = ClaudeSessionScanner.latestSession(for: b.path)?.timestamp ?? .distantPast
                return aTime > bTime
            }
        }
    }

    private func isSelected(_ worktree: WorkspaceStore.Worktree) -> Bool {
        if case .worktree(_, let path) = sidebarState.selection {
            return path == worktree.path
        }
        return false
    }
}

// MARK: - WorktreeRow

private struct WorktreeRow: View {
    let worktree: WorkspaceStore.Worktree
    let agentStatus: WorktreeAgentStatus?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: worktree.isMain ? "house.fill" : "folder")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(worktree.branch)
                .lineLimit(1)

            Spacer()

            AgentStatusDotView(status: agentStatus)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - CreateWorktreeSheet

struct CreateWorktreeSheet: View {
    @ObservedObject var store: WorkspaceStore
    let repoID: UUID
    @Binding var isPresented: Bool

    @State private var branchName: String = ""
    @State private var baseBranch: String = ""
    @State private var createNewBranch: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            Text("Create Worktree")
                .font(.headline)

            Form {
                TextField("Branch name:", text: $branchName)
                TextField("Base branch (optional):", text: $baseBranch)
                Toggle("Create new branch", isOn: $createNewBranch)
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    let base = baseBranch.isEmpty ? nil : baseBranch
                    store.createWorktree(
                        repoID: repoID,
                        branch: branchName,
                        base: base,
                        createBranch: createNewBranch
                    )
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(branchName.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 340)
    }
}
