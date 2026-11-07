/// How the player asked to start the game.
public enum LaunchRequest: Equatable, Sendable {
    /// Loads the newest save straight away (`--load-game`).
    case continueSave(path: String)
    /// Opens Factorio's main menu.
    case mainMenu
}

/// How a game session ended.
public enum SessionEnd: Equatable, Sendable {
    /// The game's entry point returned this status.
    case exited(status: Int32)
    /// The game asked to restart itself (after mod changes, for example) with these arguments.
    /// iOS can't start a process again, so the player reopens FactoriOS.
    case restartRequested(arguments: [String])
    /// FactoriOS couldn't start the game.
    case failed(reason: String)
}
