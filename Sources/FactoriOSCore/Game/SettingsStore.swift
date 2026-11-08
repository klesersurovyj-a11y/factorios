public import Foundation

/// Reads and writes the player's `GameSettings` as JSON.
public struct SettingsStore: Sendable {
    /// The JSON file the settings live in.
    public let file: URL

    /// Creates a store for the settings in `file`.
    public init(file: URL) {
        self.file = file
    }

    /// The saved settings, or the defaults when nothing was saved yet or the file can't be read.
    public func load() -> GameSettings {
        guard let data = try? Data(contentsOf: file),
            let settings = try? JSONDecoder().decode(GameSettings.self, from: data)
        else {
            // A missing file is a fresh install; an unreadable one (from a different version) starts over too.
            return .defaults
        }
        return settings
    }

    /// Saves `settings`, replacing the file in one step.
    public func save(_ settings: GameSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }
}
