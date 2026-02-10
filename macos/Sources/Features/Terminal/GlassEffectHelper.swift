import AppKit
import SwiftUI
import GhosttyKit

/// Manages the glass effect for an NSView container.
/// Both TerminalViewContainer and WorkspaceViewContainer delegate to this helper
/// to avoid duplicating the macOS 26+ glass effect logic.
final class GlassEffectHelper {
    private weak var hostView: NSView?
    private let contentView: NSView
    private var glassEffectView: NSView?
    private var glassTopConstraint: NSLayoutConstraint?
    var derivedConfig: DerivedConfig

    init(hostView: NSView, contentView: NSView, config: Ghostty.Config) {
        self.hostView = hostView
        self.contentView = contentView
        self.derivedConfig = DerivedConfig(config: config)
    }

    func updateConfig(_ config: Ghostty.Config) {
        let newValue = DerivedConfig(config: config)
        guard newValue != derivedConfig else { return }
        derivedConfig = newValue
        DispatchQueue.main.async { [weak self] in
            self?.updateGlassEffectIfNeeded()
        }
    }

    func updateGlassEffectIfNeeded() {
        guard let hostView else { return }
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), derivedConfig.backgroundBlur.isGlassStyle else {
            glassEffectView?.removeFromSuperview()
            glassEffectView = nil
            glassTopConstraint = nil
            return
        }
        guard let effectView = addGlassEffectViewIfNeeded(hostView: hostView) else {
            return
        }
        switch derivedConfig.backgroundBlur {
        case .macosGlassRegular:
            effectView.style = NSGlassEffectView.Style.regular
        case .macosGlassClear:
            effectView.style = NSGlassEffectView.Style.clear
        default:
            break
        }
        let window = hostView.window
        let backgroundColor = (window as? TerminalWindow)?.preferredBackgroundColor ?? NSColor(derivedConfig.backgroundColor)
        effectView.tintColor = backgroundColor
            .withAlphaComponent(derivedConfig.backgroundOpacity)
        if let window, window.responds(to: Selector(("_cornerRadius"))), let cornerRadius = window.value(forKey: "_cornerRadius") as? CGFloat {
            effectView.cornerRadius = cornerRadius
        }
#endif
    }

    func updateGlassEffectTopInsetIfNeeded() {
#if compiler(>=6.2)
        guard #available(macOS 26.0, *), derivedConfig.backgroundBlur.isGlassStyle else {
            return
        }
        guard glassEffectView != nil else { return }
        guard let themeFrameView = hostView?.window?.contentView?.superview else { return }
        glassTopConstraint?.constant = -themeFrameView.safeAreaInsets.top
#endif
    }

#if compiler(>=6.2)
    @available(macOS 26.0, *)
    private func addGlassEffectViewIfNeeded(hostView: NSView) -> NSGlassEffectView? {
        if let existed = glassEffectView as? NSGlassEffectView {
            updateGlassEffectTopInsetIfNeeded()
            return existed
        }
        guard let themeFrameView = hostView.window?.contentView?.superview else {
            return nil
        }
        let effectView = NSGlassEffectView()
        hostView.addSubview(effectView, positioned: .below, relativeTo: contentView)
        effectView.translatesAutoresizingMaskIntoConstraints = false
        glassTopConstraint = effectView.topAnchor.constraint(
            equalTo: hostView.topAnchor,
            constant: -themeFrameView.safeAreaInsets.top
        )
        if let glassTopConstraint {
            NSLayoutConstraint.activate([
                glassTopConstraint,
                effectView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
                effectView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
                effectView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            ])
        }
        glassEffectView = effectView
        return effectView
    }
#endif

    struct DerivedConfig: Equatable {
        var backgroundOpacity: Double = 0
        var backgroundBlur: Ghostty.Config.BackgroundBlur
        var backgroundColor: Color = .clear

        init(config: Ghostty.Config) {
            self.backgroundBlur = config.backgroundBlur
            self.backgroundOpacity = config.backgroundOpacity
            self.backgroundColor = config.backgroundColor
        }
    }
}
