import Foundation

/// File paths for agent hooks, events, and wrapper scripts.
enum AgentStatusPaths {
    /// The application support directory for Treeminal.
    static var appSupportDirectory: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("dev.treeminal.Treeminal")
    }

    /// Directory containing agent hook scripts.
    static var agentHooksDirectory: URL {
        appSupportDirectory.appendingPathComponent("agent-hooks")
    }

    /// Directory containing the claude wrapper script.
    static var agentBinDirectory: URL {
        appSupportDirectory.appendingPathComponent("agent-hooks/bin")
    }

    /// The JSONL file where agent events are written.
    static var agentEventsFile: URL {
        appSupportDirectory.appendingPathComponent("agent-events.jsonl")
    }

    /// The notify.sh script path.
    static var notifyScript: URL {
        agentHooksDirectory.appendingPathComponent("notify.sh")
    }

    /// The Claude Code settings JSON file.
    static var claudeSettingsFile: URL {
        agentHooksDirectory.appendingPathComponent("claude-settings.json")
    }

    /// The claude wrapper script.
    static var claudeWrapper: URL {
        agentBinDirectory.appendingPathComponent("claude")
    }

    /// Environment variable name for the events directory.
    static let eventsDirectoryEnvVar = "TREEMINAL_AGENT_EVENTS_DIR"

    /// Environment variable name for the bin directory.
    static let binDirectoryEnvVar = "TREEMINAL_AGENT_BIN_DIR"
}
