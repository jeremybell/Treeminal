import AppKit

/// NSToolbar for the workspace window with sidebar toggle and worktree path display.
class WorkspaceToolbar: NSToolbar, NSToolbarDelegate {

    static let worktreePathIdentifier = NSToolbarItem.Identifier("worktreePath")

    /// The path label toolbar item, updated when the active worktree changes.
    private var pathItem: NSToolbarItem?

    override init(identifier: NSToolbar.Identifier) {
        super.init(identifier: identifier)
        self.delegate = self
        self.displayMode = .iconOnly
    }

    /// Update the displayed worktree path.
    func updateWorktreePath(_ path: String?) {
        guard let item = pathItem else { return }
        if let path {
            let displayPath = abbreviatePath(path)
            if let textField = item.view as? NSTextField {
                textField.stringValue = displayPath
            }
            item.label = displayPath
        } else {
            if let textField = item.view as? NSTextField {
                textField.stringValue = ""
            }
            item.label = ""
        }
    }

    /// Abbreviate a file path for display (e.g. replace home dir with ~).
    private func abbreviatePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleSidebar:
            let item = NSToolbarItem(itemIdentifier: .toggleSidebar)
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            return item

        case Self.worktreePathIdentifier:
            let item = NSToolbarItem(itemIdentifier: Self.worktreePathIdentifier)
            item.label = ""
            item.paletteLabel = "Worktree Path"

            let textField = NSTextField(labelWithString: "")
            textField.font = NSFont.systemFont(ofSize: 13)
            textField.textColor = .secondaryLabelColor
            textField.lineBreakMode = .byTruncatingMiddle
            textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
            textField.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
            item.view = textField

            self.pathItem = item
            return item

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            Self.worktreePathIdentifier,
            .flexibleSpace,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
}
