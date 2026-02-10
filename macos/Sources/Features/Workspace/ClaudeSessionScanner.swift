import Foundation
import OSLog

/// Represents a single Claude Code session parsed from a JSONL file.
struct ClaudeSession: Identifiable, Hashable {
    /// The session UUID (derived from the filename).
    let id: String
    /// The working directory from the JSONL content.
    let cwd: String
    /// The last activity timestamp.
    let timestamp: Date
    /// The first ~60 chars of the first user message (for display).
    let snippet: String?
    /// The number of user messages in the session.
    let messageCount: Int
    /// Full path to the JSONL file.
    let sourcePath: String
}

/// Scans ~/.claude/projects/ for Claude Code JSONL session files
/// and matches them to worktree paths.
enum ClaudeSessionScanner {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "ClaudeSessionScanner"
    )

    /// Maximum bytes to read from each JSONL file (first 50KB).
    private static let maxReadBytes = 50 * 1024

    /// Maximum lines to parse per file.
    private static let maxLines = 100

    /// Scan all sessions matching a worktree path.
    static func sessions(for worktreePath: String) -> [ClaudeSession] {
        let projectsDir = claudeProjectsDirectory
        guard FileManager.default.fileExists(atPath: projectsDir.path) else { return [] }

        let normalizedWorktree = normalizedPath(worktreePath)
        var results: [ClaudeSession] = []

        do {
            let projectDirs = try FileManager.default.contentsOfDirectory(
                at: projectsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for projectDir in projectDirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: projectDir.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }

                let jsonlFiles = try FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ).filter { $0.pathExtension == "jsonl" }

                for file in jsonlFiles {
                    guard let session = parseSession(at: file) else { continue }
                    let normalizedCwd = normalizedPath(session.cwd)
                    if normalizedCwd == normalizedWorktree || normalizedCwd.hasPrefix(normalizedWorktree + "/") {
                        results.append(session)
                    }
                }
            }
        } catch {
            logger.warning("failed to scan Claude projects: \(error.localizedDescription)")
        }

        // Sort by most recent first
        return results.sorted { $0.timestamp > $1.timestamp }
    }

    /// Find the most recent session for a worktree.
    static func latestSession(for worktreePath: String) -> ClaudeSession? {
        return sessions(for: worktreePath).first
    }

    // MARK: - Private

    /// Parse a single JSONL file into a ClaudeSession.
    private static func parseSession(at url: URL) -> ClaudeSession? {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxReadBytes)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }

        let lines = text.components(separatedBy: "\n")
        let sessionID = url.deletingPathExtension().lastPathComponent

        var cwd: String?
        var snippet: String?
        var lastTimestamp: Date?
        var userMessageCount = 0
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (index, line) in lines.enumerated() {
            guard index < maxLines else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let lineData = trimmed.data(using: .utf8) else { continue }

            // Parse as generic JSON to extract fields
            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Extract cwd from top-level field
            if cwd == nil, let cwdValue = json["cwd"] as? String {
                cwd = cwdValue
            }

            // Extract timestamp
            if let tsString = json["timestamp"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let ts = formatter.date(from: tsString) {
                    lastTimestamp = ts
                } else {
                    // Try without fractional seconds
                    formatter.formatOptions = [.withInternetDateTime]
                    lastTimestamp = formatter.date(from: tsString) ?? lastTimestamp
                }
            }

            // Count user messages and extract snippet from first one
            if let msgType = json["type"] as? String, msgType == "user" {
                userMessageCount += 1
                if snippet == nil, let message = json["message"] as? [String: Any] {
                    if let content = message["content"] as? String {
                        snippet = String(content.prefix(60))
                    } else if let contentArray = message["content"] as? [[String: Any]],
                              let firstText = contentArray.first(where: { $0["type"] as? String == "text" }),
                              let text = firstText["text"] as? String {
                        snippet = String(text.prefix(60))
                    }
                }
            }
        }

        guard let cwd else { return nil }

        return ClaudeSession(
            id: sessionID,
            cwd: cwd,
            timestamp: lastTimestamp ?? fileModificationDate(url) ?? Date.distantPast,
            snippet: snippet,
            messageCount: userMessageCount,
            sourcePath: url.path
        )
    }

    /// The ~/.claude/projects/ directory.
    private static var claudeProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    /// Normalize a path by resolving symlinks.
    private static func normalizedPath(_ path: String) -> String {
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Get file modification date as fallback timestamp.
    private static func fileModificationDate(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
