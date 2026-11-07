public import Foundation

/// Where FactoriOS keeps the imported game, the converted library and the player's files.
///
/// The player's Factorio folder (saves, mods, config) lives in Documents so it shows up in the Files app.
/// The imported game and everything derived from it live in Application Support, out of the player's way.
public struct GamePaths: Sendable, Equatable {
    /// Application Support/FactoriOS.
    public let support: URL
    /// Documents.
    public let documents: URL

    /// Creates the layout under the given container directories.
    public init(support: URL, documents: URL) {
        self.support = support
        self.documents = documents
    }

    /// The layout in the app's own container.
    public static func standard(fileManager: FileManager = .default) throws -> Self {
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let documentsRoot = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return Self(
            support: supportRoot.appendingPathComponent("FactoriOS", isDirectory: true),
            documents: documentsRoot
        )
    }

    /// The imported `factorio.app`.
    public var gameApp: URL { support.appendingPathComponent("Game/factorio.app", isDirectory: true) }
    /// A partial import, renamed to `gameApp` once complete.
    public var gameImporting: URL { support.appendingPathComponent("Game/factorio.app.importing", isDirectory: true) }
    /// The game's read-only data directory (`read-data`).
    public var gameData: URL { gameApp.appendingPathComponent("Contents/data", isDirectory: true) }
    /// The game's original macOS executable.
    public var gameExecutable: URL { gameApp.appendingPathComponent("Contents/MacOS/factorio") }
    /// Facts about the imported game, written by the importer.
    public var gameInfo: URL { support.appendingPathComponent("Game/game.json") }

    /// The converted, signed game library that FactoriOS loads.
    public var convertedLibrary: URL { support.appendingPathComponent("Converted/factorio.dylib") }
    /// The converter's record of which pointer slots the compatibility layer fills in.
    public var slotManifest: URL { support.appendingPathComponent("Converted/slots.json") }

    /// The player's Factorio folder (`write-data`): saves, mods, config, scenarios.
    public var writeData: URL { documents.appendingPathComponent("Factorio", isDirectory: true) }
    /// Factorio's `config.ini`.
    public var config: URL { writeData.appendingPathComponent("config/config.ini") }
    /// The saves directory.
    public var saves: URL { writeData.appendingPathComponent("saves", isDirectory: true) }
    /// Factorio's own log of the current run.
    public var gameLog: URL { writeData.appendingPathComponent("factorio-current.log") }

    /// FactoriOS's logs: the game's stdout/stderr and FactoriOS's own messages.
    public var logs: URL { support.appendingPathComponent("Logs", isDirectory: true) }
    /// FactoriOS's settings and controller layout.
    public var settingsFile: URL { support.appendingPathComponent("settings.json") }
    /// The on-screen controller layout.
    public var padLayoutFile: URL { support.appendingPathComponent("pad-layout.json") }
    /// The host app's Apple Development identity, exported as PKCS#12.
    public var signingIdentity: URL { support.appendingPathComponent("Signing/identity.p12") }
}
