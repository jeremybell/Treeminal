import Foundation
import OSLog

/// Tails the agent events JSONL file and emits parsed events via callback.
/// Uses DispatchSource for kernel-level file monitoring (kqueue).
final class AgentEventTailer {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "AgentEventTailer"
    )

    private let filePath: URL
    private let onEvent: (AgentLifecycleEvent) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileHandle: FileHandle?
    private var readOffset: UInt64 = 0
    private let queue = DispatchQueue(label: "dev.treeminal.agent-event-tailer")

    /// Maximum file size before truncation (1 MB).
    private static let maxFileSize: UInt64 = 1_024 * 1_024

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(filePath: URL, onEvent: @escaping (AgentLifecycleEvent) -> Void) {
        self.filePath = filePath
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            self?.setupMonitoring()
        }
    }

    func stop() {
        queue.sync {
            source?.cancel()
            source = nil
            // fileHandle is closed by the cancel handler
        }
    }

    private func setupMonitoring() {
        // Ensure the file exists
        let fm = FileManager.default
        let dir = filePath.deletingLastPathComponent().path
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: filePath.path) {
            fm.createFile(atPath: filePath.path, contents: nil)
        }

        // Truncate if the file has grown too large
        truncateIfNeeded()

        guard let handle = FileHandle(forReadingAtPath: filePath.path) else {
            Self.logger.error("failed to open agent events file for reading")
            return
        }
        self.fileHandle = handle

        // Seek to end so we only read new events
        handle.seekToEndOfFile()
        readOffset = handle.offsetInFile

        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewData()
        }

        source.setCancelHandler { [weak self] in
            try? self?.fileHandle?.close()
            self?.fileHandle = nil
        }

        self.source = source
        source.resume()
    }

    private func readNewData() {
        guard let handle = fileHandle else { return }

        handle.seek(toFileOffset: readOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }
        readOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8) else { return }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }

            do {
                let event = try decoder.decode(AgentLifecycleEvent.self, from: lineData)
                DispatchQueue.main.async { [weak self] in
                    self?.onEvent(event)
                }
            } catch {
                Self.logger.warning("failed to parse agent event: \(error.localizedDescription)")
            }
        }
    }

    /// Truncate the events file if it exceeds the size limit.
    private func truncateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: filePath.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize > Self.maxFileSize else { return }

        Self.logger.info("agent events file exceeded \(Self.maxFileSize) bytes, truncating")
        // Simply truncate to empty -- we only care about new events going forward
        if let handle = FileHandle(forWritingAtPath: filePath.path) {
            handle.truncateFile(atOffset: 0)
            try? handle.close()
        }
    }
}
