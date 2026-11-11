import FactoriOSCore
import Foundation
import Observation

/// The launcher's own state: the player's settings, saved as they change, and their saves.
@MainActor
@Observable
final class LauncherModel {
    /// Where everything is.
    let paths: GamePaths
    private let library: SaveLibrary

    /// The player's settings; every change is saved at once.
    var settings: GameSettings {
        didSet {
            guard settings != oldValue else {
                // Set to what it was: nothing to save.
                return
            }
            saveSettings()
        }
    }

    /// Why the settings couldn't be saved, if they couldn't.
    private(set) var settingsError: String?
    /// The player's saves, newest first.
    private(set) var saves: [SaveFile] = []
    /// Why the saves couldn't be listed, if they couldn't.
    private(set) var savesError: String?

    /// Loads the settings and lists the saves in `paths`.
    init(paths: GamePaths) {
        self.paths = paths
        library = SaveLibrary(paths: paths)
        settings = GameSettings.load(from: paths.settingsFile)
        refreshSaves()
    }

    /// The save Continue loads.
    var newestSave: SaveFile? { saves.first }

    /// The player's Factorio folder in the Files app; it's created first, so Files has something to open.
    var filesURL: URL? {
        try? FileManager.default.createDirectory(at: paths.writeData, withIntermediateDirectories: true)
        let path = paths.writeData.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        return path.flatMap { URL(string: "shareddocuments://" + $0) }
    }

    /// Lists the saves again: the game or the Files app may have changed them.
    func refreshSaves() {
        do {
            saves = try library.saves()
            savesError = nil
        } catch {
            saves = []
            savesError = error.localizedDescription
        }
    }

    /// Imports the saves the player picked.
    ///
    /// - Returns: What happened, to show the player.
    func importSaves(_ urls: [URL]) -> String {
        let before = Set(saves.map(\.url))
        var failures: [String] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try library.importSave(from: url)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        refreshSaves()
        let added = saves.filter { !before.contains($0.url) }.count
        let summary =
            switch added {
            case 0:
                "Nothing new: those saves are already here."
            case 1:
                "Added 1 save. It's in Factorio's Load game."
            default:
                "Added \(added) saves. They're in Factorio's Load game."
            }
        return failures.isEmpty ? summary : ([summary] + failures).joined(separator: "\n")
    }

    /// Copies every save into a fresh folder in the app's temporary directory, for the player to export.
    ///
    /// - Returns: The folder.
    func exportFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Factorio saves", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        try library.exportAll(to: folder)
        return folder
    }

    private func saveSettings() {
        do {
            try settings.save(to: paths.settingsFile)
            settingsError = nil
        } catch {
            settingsError = "Couldn't save the settings: \(error.localizedDescription)"
        }
    }
}
