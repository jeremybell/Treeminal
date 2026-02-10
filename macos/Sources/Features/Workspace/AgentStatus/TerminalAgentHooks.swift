import Foundation
import GhosttyKit

/// Applies agent hook environment variables to a SurfaceConfiguration.
enum TerminalAgentHooks {
    /// Configures the given surface configuration with agent hook env vars
    /// so that Claude Code uses our wrapper and writes events.
    static func apply(to config: inout Ghostty.SurfaceConfiguration) {
        let eventsDir = AgentStatusPaths.appSupportDirectory.path
        let binDir = AgentStatusPaths.agentBinDirectory.path

        config.environmentVariables[AgentStatusPaths.eventsDirectoryEnvVar] = eventsDir
        config.environmentVariables[AgentStatusPaths.binDirectoryEnvVar] = binDir

        // Prepend our bin directory to PATH so the claude wrapper is found first.
        // The shell will inherit this PATH and resolve our wrapper before the real binary.
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        config.environmentVariables["PATH"] = "\(binDir):\(currentPath)"
    }
}
