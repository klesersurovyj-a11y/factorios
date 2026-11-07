import Foundation

/// Why the converted game couldn't be started.
enum GameLaunchError: Error, LocalizedError, Equatable {
    /// The converted library or its slot manifest is missing or unreadable.
    case notInstalled
    /// dyld refused the converted library.
    case loadFailed(String)
    /// The loaded library isn't among dyld's images.
    case imageNotFound
    /// The library has no LC_MAIN entry point.
    case noEntryPoint
    /// The slot manifest names a symbol the compatibility layer doesn't replace.
    case noReplacement(symbol: String)
    /// The slot manifest points outside the loaded image.
    case slotOutsideImage(symbol: String)
    /// A slot couldn't be written (Mach error).
    case slotNotWritable(symbol: String, code: Int32)
    /// The game's log file couldn't be opened.
    case logUnavailable(code: Int32)
    /// SDL couldn't attach the on-screen controller.
    case gamepadUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "The game isn't installed. Import the Factorio .dmg again."
        case .loadFailed(let reason):
            "iOS refused to load the game: \(reason)"
        case .imageNotFound:
            "The game loaded but can't be found in memory."
        case .noEntryPoint:
            "The game has no entry point."
        case .noReplacement(let symbol):
            "The installed game needs \(symbol), which this FactoriOS doesn't provide. Import the .dmg again."
        case .slotOutsideImage(let symbol):
            "The installed game's record for \(symbol) doesn't match it. Import the .dmg again."
        // swiftlint's pattern_matching_keywords wants `case let .x(a, b)`, which swift-format's
        // UseLetInEveryBoundCaseVariable rejects; the two rules contradict, so swift-format's form is kept.
        // swiftlint:disable:next pattern_matching_keywords
        case .slotNotWritable(let symbol, let code):
            "The game's reference to \(symbol) can't be redirected (error \(code))."
        case .logUnavailable(let code):
            "The game's log can't be created (error \(code))."
        case .gamepadUnavailable(let reason):
            "The on-screen controller can't be connected: \(reason)"
        }
    }
}
