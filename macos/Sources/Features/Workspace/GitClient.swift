import Foundation
import OSLog

/// Static utility for running git commands via Process.
enum GitClient {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "GitClient"
    )

    struct WorktreeInfo: Identifiable, Hashable {
        var id: String { path }
        let path: String
        let head: String
        let branch: String?
        let isMain: Bool
    }

    enum GitError: LocalizedError {
        case notARepository
        case commandFailed(String)
        case gitNotFound

        var errorDescription: String? {
            switch self {
            case .notARepository: return "Not a git repository"
            case .commandFailed(let msg): return "Git command failed: \(msg)"
            case .gitNotFound: return "git executable not found"
            }
        }
    }

    // MARK: - Public API

    static func isGitRepository(path: String) -> Bool {
        let (_, status) = runGit(args: ["-C", path, "rev-parse", "--git-dir"])
        return status == 0
    }

    static func listWorktrees(repoPath: String) throws -> [WorktreeInfo] {
        let (output, status) = runGit(args: ["-C", repoPath, "worktree", "list", "--porcelain"])
        guard status == 0 else {
            throw GitError.commandFailed(output)
        }
        return parsePorcelainWorktreeList(output)
    }

    @discardableResult
    static func addWorktree(
        repoPath: String,
        branch: String,
        base: String?,
        createBranch: Bool
    ) throws -> String {
        let worktreePath = (repoPath as NSString)
            .deletingLastPathComponent
            .appending("/\(branch)")

        var args = ["-C", repoPath, "worktree", "add"]
        if createBranch {
            args.append("-b")
            args.append(branch)
            args.append(worktreePath)
            if let base {
                args.append(base)
            }
        } else {
            args.append(worktreePath)
            args.append(branch)
        }

        let (output, status) = runGit(args: args)
        guard status == 0 else {
            throw GitError.commandFailed(output)
        }
        return worktreePath
    }

    static func removeWorktree(
        repoPath: String,
        worktreePath: String,
        force: Bool = false
    ) throws {
        var args = ["-C", repoPath, "worktree", "remove", worktreePath]
        if force {
            args.append("--force")
        }
        let (output, status) = runGit(args: args)
        guard status == 0 else {
            throw GitError.commandFailed(output)
        }
    }

    // MARK: - Private

    private static func runGit(args: [String]) -> (String, Int32) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.standardOutput = pipe
        process.standardError = pipe

        // Ensure git can be found in common locations
        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        if let existing = env["PATH"] {
            env["PATH"] = "\(extraPaths):\(existing)"
        } else {
            env["PATH"] = extraPaths
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.error("failed to run git: \(error.localizedDescription)")
            return (error.localizedDescription, -1)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, process.terminationStatus)
    }

    private static func parsePorcelainWorktreeList(_ output: String) -> [WorktreeInfo] {
        var worktrees: [WorktreeInfo] = []
        var currentPath: String?
        var currentHead: String?
        var currentBranch: String?
        var isFirst = true

        for line in output.components(separatedBy: "\n") {
            if line.isEmpty {
                // End of block
                if let path = currentPath, let head = currentHead {
                    worktrees.append(WorktreeInfo(
                        path: path,
                        head: head,
                        branch: currentBranch,
                        isMain: isFirst
                    ))
                    isFirst = false
                }
                currentPath = nil
                currentHead = nil
                currentBranch = nil
            } else if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                currentHead = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let fullRef = String(line.dropFirst("branch ".count))
                // Strip refs/heads/ prefix
                if fullRef.hasPrefix("refs/heads/") {
                    currentBranch = String(fullRef.dropFirst("refs/heads/".count))
                } else {
                    currentBranch = fullRef
                }
            }
        }

        // Handle last block if no trailing newline
        if let path = currentPath, let head = currentHead {
            worktrees.append(WorktreeInfo(
                path: path,
                head: head,
                branch: currentBranch,
                isMain: isFirst
            ))
        }

        return worktrees
    }
}
