import FactoriOSCore
import Foundation

/// Facts about the imported game, which `scripts/deploy` saves next to it.
struct ImportedGame: Decodable, Sendable {
    /// The game's version, such as `2.1.23`.
    let version: String
    /// Whether this is the free demo.
    let isDemo: Bool

    /// The installed game, from `paths.gameInfo`; nil when no game has been imported or the record is unreadable.
    static func installed(paths: GamePaths) -> Self? {
        readJSON(from: paths.gameInfo)
    }
}
