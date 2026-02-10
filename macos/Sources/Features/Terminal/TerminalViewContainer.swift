import AppKit
import SwiftUI

/// Use this container to achieve a glass effect at the window level.
/// Modifying `NSThemeFrame` can sometimes be unpredictable.
class TerminalViewContainer<ViewModel: TerminalViewModel>: NSView {
    private let terminalView: NSView
    private var glassHelper: GlassEffectHelper!

    init(ghostty: Ghostty.App, viewModel: ViewModel, delegate: (any TerminalViewDelegate)? = nil) {
        self.terminalView = NSHostingView(rootView: TerminalView(
            ghostty: ghostty,
            viewModel: viewModel,
            delegate: delegate
        ))
        super.init(frame: .zero)
        self.glassHelper = GlassEffectHelper(
            hostView: self,
            contentView: terminalView,
            config: ghostty.config
        )
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// To make ``TerminalController/DefaultSize/contentIntrinsicSize``
    /// work in ``TerminalController/windowDidLoad()``,
    /// we override this to provide the correct size.
    override var intrinsicContentSize: NSSize {
        terminalView.intrinsicContentSize
    }

    private func setup() {
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
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
