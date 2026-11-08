import FactoriOSCore
import Foundation

/// A Factorio save in the player's saves folder.
struct SaveFile: Sendable, Equatable, Identifiable {
    /// Where the save is.
    let url: URL
    /// The save's name, as Factorio shows it: the file name without `.zip`.
    let name: String
    /// When the game last wrote it.
    let modified: Date

    /// The save's file identifies it.
    var id: URL { url }
}

/// Why a save couldn't be imported.
enum SaveLibraryError: Error, LocalizedError, Equatable {
    /// The file isn't a zip archive, so it can't be a Factorio save.
    case notASave(name: String)

    /// What the player sees.
    var errorDescription: String? {
        switch self {
        case .notASave(let name):
            "\(name) isn't a Factorio save: saves are .zip files."
        }
    }
}

/// The player's saves: listing, importing and exporting them.
struct SaveLibrary: Sendable {
    /// The start of every zip archive: "PK", 3, 4.
    private static let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])

    private let folder: URL

    /// Creates the library for the saves folder in `paths`.
    init(paths: GamePaths) {
        folder = paths.saves
    }

    /// Every save, newest first.
    func saves() throws -> [SaveFile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.path) else {
            return []
        }
        let urls = try manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var saves: [SaveFile] = []
        for url in urls where url.pathExtension.lowercased() == "zip" {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                continue
            }
            let name = url.deletingPathExtension().lastPathComponent
            saves.append(SaveFile(url: url, name: name, modified: values.contentModificationDate ?? .distantPast))
        }
        return saves.sorted { $0.modified > $1.modified }
    }

    /// Copies the save at `source` into the saves folder.
    ///
    /// The same file imported again changes nothing; a different save with the same name gets a numbered name,
    /// so an import never overwrites the player's progress.
    func importSave(from source: URL) throws {
        let manager = FileManager.default
        let fileName = source.lastPathComponent
        let handle = try FileHandle(forReadingFrom: source)
        let start = try handle.read(upToCount: Self.zipSignature.count)
        try handle.close()
        guard start == Self.zipSignature else {
            throw SaveLibraryError.notASave(name: fileName)
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        var destination = folder.appendingPathComponent(base + ".zip")
        var number = 2
        while manager.fileExists(atPath: destination.path) {
            if manager.contentsEqual(atPath: destination.path, andPath: source.path) {
                // Already imported: nothing to do.
                return
            }
            destination = folder.appendingPathComponent("\(base) (\(number)).zip")
            number += 1
        }
        try manager.copyItem(at: source, to: destination)
    }

    /// Copies every save into the directory `destination`, creating it, replacing older copies of the same name.
    func exportAll(to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        for save in try saves() {
            let target = destination.appendingPathComponent(save.url.lastPathComponent)
            if manager.fileExists(atPath: target.path) {
                try manager.removeItem(at: target)
            }
            try manager.copyItem(at: save.url, to: target)
        }
    }
}
