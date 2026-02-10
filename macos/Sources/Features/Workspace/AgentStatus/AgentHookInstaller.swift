import Foundation
import OSLog

/// Installs hook scripts that allow Claude Code to report agent lifecycle events.
enum AgentHookInstaller {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentHookInstaller"
    )

    /// Install all agent hook files. Safe to call multiple times; will overwrite existing files.
    static func install() {
        let fm = FileManager.default

        // Create directories
        let dirs = [
            AgentStatusPaths.agentHooksDirectory,
            AgentStatusPaths.agentBinDirectory,
        ]
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                do {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                } catch {
                    logger.error("failed to create directory \(dir.path): \(error.localizedDescription)")
                    return
                }
            }
        }

        // Install notify.sh
        installNotifyScript()

        // Install claude-settings.json
        installClaudeSettings()

        // Install claude wrapper
        installClaudeWrapper()
    }

    // MARK: - Private

    private static func installNotifyScript() {
        let eventsFile = AgentStatusPaths.agentEventsFile.path
        let script = """
        #!/bin/bash
        # Treeminal agent hook notification script
        # Writes agent lifecycle events as JSONL to the events file.

        EVENT_TYPE="$1"
        CWD="${TREEMINAL_CWD:-$(pwd)}"
        TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        EVENTS_FILE="\(eventsFile)"

        # Ensure events directory exists
        mkdir -p "$(dirname "$EVENTS_FILE")"

        # Escape special JSON characters in CWD to prevent injection
        escape_json() {
            local s="$1"
            s="${s//\\\\/\\\\\\\\}"
            s="${s//\\"/\\\\\\"}"
            s="${s//$'\\n'/\\\\n}"
            s="${s//$'\\r'/\\\\r}"
            s="${s//$'\\t'/\\\\t}"
            printf '%s' "$s"
        }

        SAFE_CWD="$(escape_json "$CWD")"

        # Write the event as JSON
        printf '{"timestamp":"%s","eventType":"%s","cwd":"%s"}\\n' \
            "$TIMESTAMP" "$EVENT_TYPE" "$SAFE_CWD" >> "$EVENTS_FILE"
        """

        writeFile(at: AgentStatusPaths.notifyScript, contents: script, executable: true)
    }

    private static func installClaudeSettings() {
        let notifyPath = AgentStatusPaths.notifyScript.path
        let settings: [String: Any] = [
            "hooks": [
                "UserPromptSubmit": [
                    ["type": "command", "command": "\(notifyPath) start"]
                ],
                "Stop": [
                    ["type": "command", "command": "\(notifyPath) stop"]
                ],
                "PermissionRequest": [
                    ["type": "command", "command": "\(notifyPath) permissionRequest"]
                ],
                "SessionEnd": [
                    ["type": "command", "command": "\(notifyPath) sessionEnd"]
                ],
            ]
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            if let jsonString = String(data: data, encoding: .utf8) {
                writeFile(at: AgentStatusPaths.claudeSettingsFile, contents: jsonString, executable: false)
            }
        } catch {
            logger.error("failed to serialize claude settings: \(error.localizedDescription)")
        }
    }

    private static func installClaudeWrapper() {
        let settingsPath = AgentStatusPaths.claudeSettingsFile.path

        let wrapper = """
        #!/bin/bash
        # Treeminal Claude wrapper script
        # Finds the real claude binary and injects --settings to enable hooks.

        # Export CWD for the notify script
        export TREEMINAL_CWD="$(pwd)"

        # Resolve symlinks portably (works on macOS without GNU coreutils)
        resolve_path() {
            local target="$1"
            while [ -L "$target" ]; do
                local dir="$(cd -P "$(dirname "$target")" && pwd)"
                target="$(readlink "$target")"
                # Handle relative symlinks
                [[ "$target" != /* ]] && target="$dir/$target"
            done
            echo "$(cd -P "$(dirname "$target")" && pwd)/$(basename "$target")"
        }

        # Find the real claude binary, skipping ourselves
        SELF="$(resolve_path "$0")"

        REAL_CLAUDE=""
        IFS=':' read -ra DIRS <<< "$PATH"
        for dir in "${DIRS[@]}"; do
            candidate="$dir/claude"
            if [ -x "$candidate" ] && [ "$(resolve_path "$candidate")" != "$SELF" ]; then
                REAL_CLAUDE="$candidate"
                break
            fi
        done

        if [ -z "$REAL_CLAUDE" ]; then
            echo "Error: Could not find the real claude binary in PATH" >&2
            exit 1
        fi

        exec "$REAL_CLAUDE" --settings "\(settingsPath)" "$@"
        """

        writeFile(at: AgentStatusPaths.claudeWrapper, contents: wrapper, executable: true)
    }

    private static func writeFile(at url: URL, contents: String, executable: Bool) {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            if executable {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755],
                    ofItemAtPath: url.path
                )
            }
        } catch {
            logger.error("failed to write \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
