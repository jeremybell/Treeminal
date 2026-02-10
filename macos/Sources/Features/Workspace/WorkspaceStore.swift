import Foundation
import Combine
import OSLog
import UserNotifications

/// Central state manager for repositories, worktrees, and agent status.
/// All @Published properties must be accessed on the main thread.
final class WorkspaceStore: ObservableObject {

    // MARK: - Types

    struct Repository: Identifiable, Codable, Hashable {
        let id: UUID
        var path: String
        var name: String

        init(id: UUID = UUID(), path: String) {
            self.id = id
            self.path = path
            self.name = (path as NSString).lastPathComponent
        }
    }

    struct Worktree: Identifiable, Hashable {
        var id: String { path }
        let repositoryID: UUID
        let branch: String
        let path: String
        let isMain: Bool
    }

    // MARK: - Published State

    @Published var repositories: [Repository] = []
    @Published var worktreesByRepoID: [UUID: [Worktree]] = [:]
    @Published var agentStatusByWorktreePath: [String: AgentStatusEntry] = [:]
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Private

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "WorkspaceStore"
    )

    private static let reposKey = "WorkspaceStore.repositories"

    // MARK: - Init

    init() {
        loadRepositories()
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.refreshAllAsync()
        }
    }

    // MARK: - Repository Management

    func addRepository(path: String) {
        // Don't add duplicates
        guard !repositories.contains(where: { $0.path == path }) else { return }

        let pathCopy = path
        Task.detached(priority: .userInitiated) {
            let isRepo = GitClient.isGitRepository(path: pathCopy)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard isRepo else {
                    self.errorMessage = "\(pathCopy) is not a git repository."
                    return
                }
                let repo = Repository(path: pathCopy)
                self.repositories.append(repo)
                self.saveRepositories()
                Task.detached(priority: .userInitiated) { [weak self] in
                    await self?.refreshWorktrees(for: repo)
                }
            }
        }
    }

    func removeRepository(id: UUID) {
        repositories.removeAll { $0.id == id }
        worktreesByRepoID.removeValue(forKey: id)
        saveRepositories()
    }

    func refreshAll() {
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.refreshAllAsync()
        }
    }

    // MARK: - Worktree Management

    func createWorktree(
        repoID: UUID,
        branch: String,
        base: String?,
        createBranch: Bool
    ) {
        guard let repo = repositories.first(where: { $0.id == repoID }) else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try GitClient.addWorktree(
                    repoPath: repo.path,
                    branch: branch,
                    base: base,
                    createBranch: createBranch
                )
                await self?.refreshWorktrees(for: repo)
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func removeWorktree(repoID: UUID, path: String, force: Bool = false) {
        guard let repo = repositories.first(where: { $0.id == repoID }) else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try GitClient.removeWorktree(
                    repoPath: repo.path,
                    worktreePath: path,
                    force: force
                )
                await self?.refreshWorktrees(for: repo)
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Agent Status

    func updateAgentStatus(for worktreePath: String, event: AgentLifecycleEvent) {
        let status: WorktreeAgentStatus?
        switch event.eventType {
        case .start:
            status = .working
        case .permissionRequest:
            status = .permission
        case .stop:
            status = .review
        case .sessionEnd:
            status = nil
        }

        if let status {
            agentStatusByWorktreePath[worktreePath] = AgentStatusEntry(
                status: status,
                updatedAt: event.timestamp
            )
        } else {
            agentStatusByWorktreePath.removeValue(forKey: worktreePath)
        }
    }

    func acknowledgeAgentStatus(for worktreePath: String) {
        // Clear review status when user clicks on the worktree
        if let entry = agentStatusByWorktreePath[worktreePath],
           entry.status == .review {
            agentStatusByWorktreePath.removeValue(forKey: worktreePath)
        }
    }

    /// Find the worktree path that best matches a given working directory.
    func findWorktreePath(for cwd: String) -> String? {
        // Find the worktree whose path is a prefix of the cwd (longest match)
        let allPaths = worktreesByRepoID.values.flatMap { $0 }.map(\.path)
        return allPaths
            .filter { cwd.hasPrefix($0) }
            .max(by: { $0.count < $1.count })
    }

    // MARK: - Persistence

    private func saveRepositories() {
        do {
            let data = try JSONEncoder().encode(repositories)
            UserDefaults.standard.set(data, forKey: Self.reposKey)
        } catch {
            Self.logger.error("failed to save repositories: \(error.localizedDescription)")
        }
    }

    private func loadRepositories() {
        guard let data = UserDefaults.standard.data(forKey: Self.reposKey) else { return }
        do {
            repositories = try JSONDecoder().decode([Repository].self, from: data)
        } catch {
            Self.logger.error("failed to load repositories: \(error.localizedDescription)")
        }
    }

    // MARK: - Refresh

    private func refreshAllAsync() async {
        await MainActor.run { [weak self] in
            self?.isRefreshing = true
        }
        // Snapshot repos on main actor
        let repos = await repositories
        for repo in repos {
            await refreshWorktrees(for: repo)
        }
        await MainActor.run { [weak self] in
            self?.isRefreshing = false
        }
    }

    private func refreshWorktrees(for repo: Repository) async {
        // Run blocking git operation off the main thread
        let repoPath = repo.path
        let repoID = repo.id
        let repoName = repo.name
        do {
            let infos = try GitClient.listWorktrees(repoPath: repoPath)
            let worktrees = infos.map { info in
                Worktree(
                    repositoryID: repoID,
                    branch: info.branch ?? "(detached)",
                    path: info.path,
                    isMain: info.isMain
                )
            }
            await MainActor.run { [weak self] in
                self?.worktreesByRepoID[repoID] = worktrees
            }
        } catch {
            Self.logger.error("failed to list worktrees for \(repoPath): \(error.localizedDescription)")
            await MainActor.run { [weak self] in
                self?.errorMessage = "Failed to list worktrees for \(repoName): \(error.localizedDescription)"
            }
        }
    }
}
