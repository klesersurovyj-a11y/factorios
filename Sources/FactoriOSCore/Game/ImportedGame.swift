import Foundation

/// Facts about the imported game, which `scripts/device` saves next to it.
public struct ImportedGame: Decodable, Sendable {
    /// The game's version, such as `2.1.23`.
    public let version: String
    /// Whether this is the free demo.
    public let isDemo: Bool

    /// The installed game, from `paths.gameInfo`; nil when no game has been imported or the record is unreadable.
    public static func installed(paths: GamePaths) -> Self? {
        (try? Data(contentsOf: paths.gameInfo)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}
