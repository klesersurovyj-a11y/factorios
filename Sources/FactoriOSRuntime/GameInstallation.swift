public import FactoriOSCore

/// The imported game and the converted library that the device build embedded in the app bundle.
@MainActor
public final class GameInstallation {
    /// Where the installation stands.
    public enum Stage: Sendable {
        /// Nothing is installed yet.
        case notInstalled
        /// The game is ready to start.
        case ready(ImportedGame)
    }

    /// Where the installation stands.
    public let stage: Stage

    /// Reads the state of the installation in `paths`.
    public init(paths: GamePaths) {
        if let game = GameImporter.installedGame(paths: paths), GameLibrary.isBundled(paths: paths) {
            stage = .ready(game)
        } else {
            stage = .notInstalled
        }
    }
}
