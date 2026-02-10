import AppKit
import SwiftUI
import GhosttyKit

/// NSView wrapping the WorkspaceView in an NSHostingView.
/// Delegates glass effect handling to GlassEffectHelper.
class WorkspaceViewContainer<ViewModel: TerminalViewModel>: NSView {
    private let hostingView: NSView
    private var glassHelper: GlassEffectHelper!

    init(
        ghostty: Ghostty.App,
        viewModel: ViewModel,
        store: WorkspaceStore,
        sidebarState: WorkspaceSidebarState,
        delegate: (any TerminalViewDelegate)?,
        onSelectWorktree: @escaping (WorkspaceStore.Worktree) -> Void,
        onResumeSession: @escaping (WorkspaceStore.Worktree) -> Void,
        onAddTerminal: @escaping (WorkspaceStore.Worktree) -> Void
    ) {
        self.hostingView = NSHostingView(rootView: WorkspaceView(
            ghostty: ghostty,
            viewModel: viewModel,
            store: store,
            sidebarState: sidebarState,
            delegate: delegate,
            onSelectWorktree: onSelectWorktree,
            onResumeSession: onResumeSession,
            onAddTerminal: onAddTerminal
        ))
        super.init(frame: .zero)
        self.glassHelper = GlassEffectHelper(
            hostView: self,
            contentView: hostingView,
            config: ghostty.config
        )
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        hostingView.intrinsicContentSize
    }

    private func setup() {
        addSubview(hostingView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ghosttyConfigDidChange(_:)),
            name: .ghosttyConfigDidChange,
            object: nil
        )
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        glassHelper.updateGlassEffectIfNeeded()
        glassHelper.updateGlassEffectTopInsetIfNeeded()
    }

    override func layout() {
        super.layout()
        glassHelper.updateGlassEffectTopInsetIfNeeded()
    }

    @objc private func ghosttyConfigDidChange(_ notification: Notification) {
        guard let config = notification.userInfo?[
            Notification.Name.GhosttyConfigChangeKey
        ] as? Ghostty.Config else { return }
        glassHelper.updateConfig(config)
    }
}
