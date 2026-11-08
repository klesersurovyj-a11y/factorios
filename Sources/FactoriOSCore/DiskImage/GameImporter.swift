public import Foundation

/// Facts about the imported game, saved next to it.
public struct ImportedGame: Codable, Sendable, Equatable {
    /// The game's version, such as `2.1.23`.
    public let version: String
    /// Whether this is the free demo.
    public let isDemo: Bool

    /// Creates the record.
    public init(version: String, isDemo: Bool) {
        self.version = version
        self.isDemo = isDemo
    }
}

/// Imports `factorio.app` from the macOS disk image the player downloaded from factorio.com.
public enum GameImporter {
    private static let appName = "factorio.app"

    /// The `version` field of `Contents/data/base/info.json`.
    private struct BaseModInfo: Decodable {
        let version: String
    }

    /// The part of `Contents/Info.plist` that tells the demo apart.
    private struct BundleInfo: Decodable {
        enum CodingKeys: String, CodingKey {
            case displayName = "CFBundleDisplayName"
        }

        let displayName: String?
    }

    /// Imports factorio.app from a disk image and returns what was imported.
    ///
    /// Finds factorio.app (at the volume root or one directory down), extracts it to `paths.gameImporting`
    /// (skipping `*.dSYM`), checks `Contents/MacOS/factorio` exists, reads the version from
    /// `Contents/data/base/info.json` and whether it is the demo from the `CFBundleDisplayName` in `Info.plist`,
    /// replaces `paths.gameApp` with it, writes `paths.gameInfo` and returns it.
    ///
    /// Runs for minutes (about 1.5 GB is decompressed).
    public static func importGame(
        from dmg: URL,
        paths: GamePaths,
        progress: @Sendable (ExtractionProgress) -> Void
    ) throws -> ImportedGame {
        let image = try UDIFImage.open(FileSource(url: dmg))
        let volume = try HFSPlusVolume(source: image.source(for: image.hfsPartition()))
        let app = try findApp(in: volume)
        let fileManager = FileManager.default
        let staging = paths.gameImporting
        try fileManager.createDirectory(at: staging.deletingLastPathComponent(), withIntermediateDirectories: true)
        try removeIfPresent(staging)
        do {
            try volume.extract(app, to: staging, skipping: { $0.hasSuffix(".dSYM") }, progress: progress)
            let game = try inspect(staging)
            try removeIfPresent(paths.gameInfo)
            try removeIfPresent(paths.gameApp)
            try fileManager.moveItem(at: staging, to: paths.gameApp)
            try JSONEncoder().encode(game).write(to: paths.gameInfo, options: .atomic)
            return game
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// The installed game, from `paths.gameInfo`; nil when no game has been imported (or the record is unreadable,
    /// which only an interrupted import leaves behind, and which a new import replaces).
    public static func installedGame(paths: GamePaths) -> ImportedGame? {
        (try? Data(contentsOf: paths.gameInfo)).flatMap { try? JSONDecoder().decode(ImportedGame.self, from: $0) }
    }

    private static func findApp(in volume: HFSPlusVolume) throws -> HFSItem {
        let top = try volume.children(of: volume.root)
        if let app = top.first(where: isApp) {
            return app
        }
        for folder in top where folder.kind == .directory {
            if let app = try volume.children(of: folder).first(where: isApp) {
                return app
            }
        }
        throw DiskImageError.gameNotFound
    }

    private static func isApp(_ item: HFSItem) -> Bool {
        item.kind == .directory && item.name.lowercased() == appName
    }

    /// Checks the extracted app and reads its version and edition.
    private static func inspect(_ app: URL) throws -> ImportedGame {
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let executable = contents.appendingPathComponent("MacOS/factorio")
        guard FileManager.default.fileExists(atPath: executable.path(percentEncoded: false)) else {
            throw DiskImageError.missingExecutable
        }
        let version: String
        do {
            let info = try Data(contentsOf: contents.appendingPathComponent("data/base/info.json"))
            version = try JSONDecoder().decode(BaseModInfo.self, from: info).version
        } catch {
            throw DiskImageError.unreadableVersion
        }
        let plist = try Data(contentsOf: contents.appendingPathComponent("Info.plist"))
        let bundle = try PropertyListDecoder().decode(BundleInfo.self, from: plist)
        return ImportedGame(version: version, isDemo: bundle.displayName?.contains("Demo") ?? false)
    }

    private static func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
