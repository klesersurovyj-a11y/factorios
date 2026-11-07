public import FactoriOSCore
public import Observation

/// The imported game and the converted library that the device build embedded in the app bundle.
@MainActor
@Observable
public final class GameInstallation {
    /// Where the installation stands.
    public enum Stage: Equatable, Sendable {
        /// Nothing is installed yet.
        case notInstalled
        /// The game is ready to start.
        case ready(ImportedGame)
    }

    /// Where the installation stands.
    public private(set) var stage: Stage

    private let paths: GamePaths

    /// Reads the state of the installation in `paths`.
    public init(paths: GamePaths) {
        self.paths = paths
        if let game = GameImporter.installedGame(paths: paths), GameLibrary.isBundled(paths: paths) {
            stage = .ready(game)
        } else {
            stage = .notInstalled
        }
    }
}
