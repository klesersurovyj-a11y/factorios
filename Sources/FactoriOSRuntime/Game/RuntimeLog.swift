import FactoriOSCore
import Foundation
import os

/// FactoriOS's own log: the unified system log, plus `factorios.log` in `GamePaths.logs` for the Logs screen.
enum RuntimeLog {
    private static let logger = Logger(subsystem: "FactoriOS", category: "runtime")

    /// The file FactoriOS's messages are appended to.
    static func file(paths: GamePaths) -> URL {
        paths.logs.appendingPathComponent("factorios.log")
    }

    /// Logs `message`, and appends it to the log file when `paths` is known.
    static func write(_ message: String, paths: GamePaths?) {
        logger.notice("\(message, privacy: .public)")
        guard let paths else {
            // Before the container's directories are known only the system log exists.
            return
        }
        let line = "\(Date().formatted(.iso8601)) \(message)\n"
        let url = file(paths: paths)
        do {
            try FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            logger.error("Can't write \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
