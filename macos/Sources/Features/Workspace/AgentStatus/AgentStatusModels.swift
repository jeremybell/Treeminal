import Foundation

/// The type of agent lifecycle event received from the hook.
enum AgentLifecycleEventType: String, Codable {
    case start
    case stop
    case permissionRequest
    case sessionEnd
}

/// A single event from the agent hook JSONL file.
struct AgentLifecycleEvent: Codable {
    let timestamp: Date
    let eventType: AgentLifecycleEventType
    let cwd: String
}

/// The current status of an agent in a worktree.
enum WorktreeAgentStatus: String {
    case working
    case permission
    case review
}

/// Tracks agent status with a timestamp for a worktree.
struct AgentStatusEntry {
    let status: WorktreeAgentStatus
    let updatedAt: Date
}
