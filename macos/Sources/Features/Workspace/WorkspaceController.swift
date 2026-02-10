import Cocoa
import SwiftUI
import Combine
import GhosttyKit
import UserNotifications
import OSLog

/// The central controller for the workspace window.
/// Subclasses BaseTerminalController to reuse all split management, surface tracking,
/// focus, clipboard, and fullscreen behavior.
class WorkspaceController: BaseTerminalController {
    override var windowNibName: NSNib.Name? { "Workspace" }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "WorkspaceController"
    )

    // MARK: - State

    /// The shared workspace store (repos, worktrees, agent status).
    let workspaceStore: WorkspaceStore

    /// The sidebar UI state.
    let sidebarState: WorkspaceSidebarState

    /// Maps worktree paths to their split trees. Only the active worktree's tree is
    /// rendered; non-visible surfaces are marked occluded.
    private var splitTreesByWorktree: [String: SplitTree<Ghostty.SurfaceView>] = [:]

    /// Tracks the focused surface UUID for each worktree so focus can be restored on switch.
    private var focusedSurfaceByWorktree: [String: UUID] = [:]

    /// The currently active worktree path, or nil if none.
    private(set) var activeWorktreePath: String? = nil

    /// The agent event tailer for monitoring Claude agent status.
    private var agentEventTailer: AgentEventTailer?

    /// Combine cancellables.
    private var cancellables: Set<AnyCancellable> = []

    /// The workspace toolbar.
    private var workspaceToolbar: WorkspaceToolbar?

    // MARK: - Init

    init(_ ghostty: Ghostty.App, workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
        self.sidebarState = WorkspaceSidebarState()

        // Initialize with an empty tree - we'll create surfaces when worktrees are selected
        super.init(ghostty, baseConfig: nil, surfaceTree: .init())

        // Auto-expand all repos
        for repo in workspaceStore.repositories {
            sidebarState.expandedRepoIDs.insert(repo.id)
        }

        // Listen for fullscreen toggle
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(onToggleFullscreen),
            name: Ghostty.Notification.ghosttyToggleFullscreen,
            object: nil)

        // Install agent hooks
        AgentHookInstaller.install()

        // Start tailing agent events
        startAgentEventTailing()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        agentEventTailer?.stop()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Window Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        guard let window else { return }

        // Disable tabbing - the sidebar IS the navigation
        window.tabbingMode = .disallowed

        // Hide the title text — the worktree path in the toolbar serves as the title
        window.titleVisibility = .hidden

        // Setup toolbar with sidebar toggle and worktree path
        let toolbar = WorkspaceToolbar(identifier: .init("WorkspaceToolbar"))
        window.toolbar = toolbar
        // .unified gives the full-height glass toolbar on macOS 26+
        window.toolbarStyle = .unified
        self.workspaceToolbar = toolbar

        // Setup the content view
        setupContentView()

        // If we have repos with worktrees, select the first one
        selectInitialWorktree()
    }

    // MARK: - Content View Setup

    private func setupContentView() {
        guard let window else { return }
        guard let contentView = window.contentView else { return }

        let container = WorkspaceViewContainer(
            ghostty: ghostty,
            viewModel: self,
            store: workspaceStore,
            sidebarState: sidebarState,
            delegate: self,
            onSelectWorktree: { [weak self] worktree in
                self?.switchToWorktree(path: worktree.path)
            },
            onResumeSession: { [weak self] worktree in
                self?.showSessionPicker(for: worktree)
            },
            onAddTerminal: { [weak self] worktree in
                self?.openTerminalInWorktree(path: worktree.path)
            }
        )

        container.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    private func selectInitialWorktree() {
        // Find the first worktree available and select it
        for repo in workspaceStore.repositories {
            if let worktrees = workspaceStore.worktreesByRepoID[repo.id],
               let first = worktrees.first {
                switchToWorktree(path: first.path)
                sidebarState.selection = .worktree(repoID: repo.id, path: first.path)
                return
            }
        }
    }

    // MARK: - Worktree Switching

    /// Switch to a worktree, saving the current state and restoring the target.
    func switchToWorktree(path: String) {
        // Save current state
        if let current = activeWorktreePath {
            splitTreesByWorktree[current] = surfaceTree
            if let focused = focusedSurface {
                focusedSurfaceByWorktree[current] = focused.id
            }

            // Mark outgoing surfaces as occluded
            for surface in surfaceTree {
                if let s = surface.surface {
                    ghostty_surface_set_occlusion(s, true)
                }
            }
        }

        activeWorktreePath = path

        // Acknowledge any agent status for this worktree
        workspaceStore.acknowledgeAgentStatus(for: path)

        // Update toolbar path display
        updateToolbarPath()

        // Restore or create
        if let existingTree = splitTreesByWorktree[path], !existingTree.isEmpty {
            surfaceTree = existingTree

            // Mark incoming surfaces as visible
            for surface in surfaceTree {
                if let s = surface.surface {
                    ghostty_surface_set_occlusion(s, false)
                }
            }

            // Restore focus
            if let savedFocusID = focusedSurfaceByWorktree[path],
               let target = surfaceTree.first(where: { $0.id == savedFocusID }) {
                DispatchQueue.main.async {
                    Ghostty.moveFocus(to: target)
                }
            }
        } else {
            createInitialTerminal(for: path)
        }

        sidebarState.hasActiveWorktree = true
    }

    /// Open a new terminal split in a worktree, switching to it first if needed.
    func openTerminalInWorktree(path: String) {
        if activeWorktreePath != path {
            switchToWorktree(path: path)
        }

        // Create a new split in the current worktree
        guard let focused = focusedSurface else { return }
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = path
        TerminalAgentHooks.apply(to: &config)
        newSplit(at: focused, direction: .right, baseConfig: config)
    }

    /// Create the first terminal surface for a worktree.
    /// Runs `claude --continue` by default to auto-resume the last session.
    private func createInitialTerminal(for path: String) {
        guard let app = ghostty.app else { return }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = path
        config.command = "claude --continue"
        TerminalAgentHooks.apply(to: &config)

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        let tree = SplitTree<Ghostty.SurfaceView>(view: surface)
        splitTreesByWorktree[path] = tree
        surfaceTree = tree
    }

    // MARK: - Session Resume

    /// Show the session picker as a sheet for a worktree.
    private func showSessionPicker(for worktree: WorkspaceStore.Worktree) {
        let sessions = ClaudeSessionScanner.sessions(for: worktree.path)

        guard let window else { return }

        let picker = SessionPickerView(
            sessions: sessions,
            onSelect: { [weak self] session in
                self?.dismissSheet()
                self?.resumeSession(in: worktree.path, session: session)
            },
            onDismiss: { [weak self] in
                self?.dismissSheet()
            }
        )

        let hostingController = NSHostingController(rootView: picker)
        hostingController.preferredContentSize = NSSize(width: 320, height: 400)

        window.beginSheet(NSWindow(contentViewController: hostingController))
    }

    /// Dismiss any currently presented sheet.
    private func dismissSheet() {
        guard let window, let sheet = window.attachedSheet else { return }
        window.endSheet(sheet)
    }

    /// Resume a specific Claude Code session in a worktree.
    /// Destroys the existing surface tree and creates a fresh one with `claude --resume`.
    func resumeSession(in worktreePath: String, session: ClaudeSession) {
        guard let app = ghostty.app else { return }

        // Validate session ID contains only safe characters (alphanumeric, hyphens, underscores)
        // to prevent command injection via crafted filenames.
        let safeChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !session.id.isEmpty,
              session.id.unicodeScalars.allSatisfy({ safeChars.contains($0) }) else {
            Self.logger.error("session ID contains unsafe characters, refusing to resume: \(session.id)")
            return
        }

        // Switch to the worktree if not already active
        if activeWorktreePath != worktreePath {
            switchToWorktree(path: worktreePath)
        }

        // Close existing surfaces in this worktree
        for surface in surfaceTree {
            if let s = surface.surface {
                ghostty_surface_set_occlusion(s, true)
            }
        }

        // Create a new surface with claude --resume
        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = worktreePath
        config.command = "claude --resume \(session.id)"
        TerminalAgentHooks.apply(to: &config)

        let surface = Ghostty.SurfaceView(app, baseConfig: config)
        let tree = SplitTree<Ghostty.SurfaceView>(view: surface)
        splitTreesByWorktree[worktreePath] = tree
        surfaceTree = tree
    }

    // MARK: - Toolbar Path

    /// Update the toolbar path display with the active worktree path.
    private func updateToolbarPath() {
        workspaceToolbar?.updateWorktreePath(activeWorktreePath)
    }

    // MARK: - Surface Tree Overrides

    override func surfaceTreeDidChange(
        from: SplitTree<Ghostty.SurfaceView>,
        to: SplitTree<Ghostty.SurfaceView>
    ) {
        super.surfaceTreeDidChange(from: from, to: to)

        // Sync to our per-worktree storage
        if let path = activeWorktreePath {
            if to.isEmpty {
                splitTreesByWorktree.removeValue(forKey: path)
                focusedSurfaceByWorktree.removeValue(forKey: path)

                // Switch to another worktree instead of closing the window
                if let nextPath = findNextWorktreePath(excluding: path) {
                    switchToWorktree(path: nextPath)
                } else {
                    activeWorktreePath = nil
                    sidebarState.hasActiveWorktree = false
                    updateToolbarPath()
                }
            } else {
                splitTreesByWorktree[path] = to
            }
        }
    }

    private func findNextWorktreePath(excluding: String) -> String? {
        for (path, tree) in splitTreesByWorktree where path != excluding && !tree.isEmpty {
            return path
        }
        // Check for available worktrees even without existing trees
        for repo in workspaceStore.repositories {
            if let worktrees = workspaceStore.worktreesByRepoID[repo.id] {
                for wt in worktrees where wt.path != excluding {
                    return wt.path
                }
            }
        }
        return nil
    }

    // MARK: - Agent Event Tailing

    private func startAgentEventTailing() {
        agentEventTailer = AgentEventTailer(
            filePath: AgentStatusPaths.agentEventsFile
        ) { [weak self] event in
            self?.handleAgentEvent(event)
        }
        agentEventTailer?.start()
    }

    private func handleAgentEvent(_ event: AgentLifecycleEvent) {
        // Find the worktree that matches this event's cwd
        let worktreePath = workspaceStore.findWorktreePath(for: event.cwd) ?? event.cwd

        // Update the store
        workspaceStore.updateAgentStatus(for: worktreePath, event: event)

        // Send macOS notification if needed
        if shouldSendNotification(for: event) {
            sendAgentNotification(worktreePath: worktreePath, event: event)
        }
    }

    private func shouldSendNotification(for event: AgentLifecycleEvent) -> Bool {
        // Only notify for permission requests and completed reviews
        guard event.eventType == .permissionRequest || event.eventType == .stop else {
            return false
        }
        // Only when app is not active / window is not key
        guard let window else { return true }
        return !window.isKeyWindow || !NSApp.isActive
    }

    private func sendAgentNotification(worktreePath: String, event: AgentLifecycleEvent) {
        let branchName = findBranchName(for: worktreePath) ?? worktreePath

        let content = UNMutableNotificationContent()
        content.categoryIdentifier = Ghostty.userNotificationCategory

        switch event.eventType {
        case .permissionRequest:
            content.title = "Claude needs your attention"
            content.body = "Claude needs permission in \(branchName)"
            content.sound = .default
        case .stop:
            content.title = "Claude finished"
            content.body = "Claude finished in \(branchName)"
        default:
            return
        }

        // Store worktree path in userInfo for handling notification tap
        content.userInfo = ["worktreePath": worktreePath]

        let request = UNNotificationRequest(
            identifier: "agent-\(worktreePath)-\(event.eventType.rawValue)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Self.logger.error("failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    private func findBranchName(for worktreePath: String) -> String? {
        for (_, worktrees) in workspaceStore.worktreesByRepoID {
            if let wt = worktrees.first(where: { $0.path == worktreePath }) {
                return wt.branch
            }
        }
        return nil
    }

    // MARK: - Notification Handling

    /// Handle a notification tap from the system - switch to the relevant worktree.
    func handleNotificationTap(worktreePath: String) {
        switchToWorktree(path: worktreePath)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Update sidebar selection
        for repo in workspaceStore.repositories {
            if let worktrees = workspaceStore.worktreesByRepoID[repo.id],
               worktrees.contains(where: { $0.path == worktreePath }) {
                sidebarState.selection = .worktree(repoID: repo.id, path: worktreePath)
                break
            }
        }
    }

    // MARK: - Fullscreen

    @objc private func onToggleFullscreen(notification: SwiftUI.Notification) {
        guard let target = notification.object as? Ghostty.SurfaceView else { return }
        guard target == self.focusedSurface else { return }

        // Get the fullscreen mode we want to toggle
        let fullscreenMode: FullscreenMode
        if let any = notification.userInfo?[Ghostty.Notification.FullscreenModeKey],
           let mode = any as? FullscreenMode {
            fullscreenMode = mode
        } else {
            Ghostty.logger.warning("no fullscreen mode specified or invalid mode, doing nothing")
            return
        }

        toggleFullscreen(mode: fullscreenMode)
    }

    // MARK: - Surface Search

    /// Find a surface across all worktree split trees (not just the active one).
    func findSurface(forUUID uuid: UUID) -> Ghostty.SurfaceView? {
        // Search active tree first
        for view in surfaceTree {
            if view.id == uuid { return view }
        }
        // Search inactive trees
        for (path, tree) in splitTreesByWorktree where path != activeWorktreePath {
            for view in tree {
                if view.id == uuid { return view }
            }
        }
        return nil
    }

    // MARK: - Static Factory

    /// The currently active workspace controllers in the application.
    static var all: [WorkspaceController] {
        return NSApplication.shared.windows.compactMap {
            $0.windowController as? WorkspaceController
        }
    }

    private static var lastCascadePoint = NSPoint(x: 0, y: 0)

    /// Create a new workspace window.
    static func newWindow(
        _ ghostty: Ghostty.App,
        workspaceStore: WorkspaceStore
    ) -> WorkspaceController {
        let c = WorkspaceController(ghostty, workspaceStore: workspaceStore)

        DispatchQueue.main.async {
            if let window = c.window {
                if !window.styleMask.contains(.fullScreen) {
                    Self.lastCascadePoint = window.cascadeTopLeft(from: Self.lastCascadePoint)
                }
            }
            c.showWindow(self)
            NSApp.activate(ignoringOtherApps: true)
        }

        return c
    }

    // MARK: - IB Actions

    @IBAction func addRepository(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        panel.prompt = "Add Repository"

        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.workspaceStore.addRepository(path: url.path)

            // Auto-expand
            if let repo = self?.workspaceStore.repositories.last {
                self?.sidebarState.expandedRepoIDs.insert(repo.id)
            }
        }
    }

    @IBAction func toggleSidebarAction(_ sender: Any?) {
        // Toggle the sidebar visibility
        switch sidebarState.columnVisibility {
        case .all:
            sidebarState.columnVisibility = .detailOnly
        default:
            sidebarState.columnVisibility = .all
        }
    }
}
