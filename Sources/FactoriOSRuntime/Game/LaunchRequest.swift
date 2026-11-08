/// How the player asked to start the game.
enum LaunchRequest: Equatable, Sendable {
    /// Loads the newest save straight away (`--load-game`).
    case continueSave(path: String)
    /// Opens Factorio's main menu.
    case mainMenu
}
