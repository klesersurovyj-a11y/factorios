// Converts the imported game's macOS executable into the unsigned iOS library and slot manifest the device build
// embeds. `deploy` imports the game before and signs the library after.
//
// Usage: factorios-convert <directory>, which holds Game/factorio.app; writes Converted/.

import FactoriOSCore
import Foundation

let arguments = CommandLine.arguments.dropFirst()

guard arguments.count == 1, let directory = arguments.first else {
    FileHandle.standardError.write(Data("usage: factorios-convert DIRECTORY\n".utf8))
    exit(EXIT_FAILURE)
}

let paths = GamePaths(
    support: URL(fileURLWithPath: directory, isDirectory: true),
    documents: FileManager.default.temporaryDirectory
)

do {
    // Mapped, not read: the executable is over 200 MB.
    let executable = try Data(contentsOf: paths.gameExecutable, options: .alwaysMapped)
    let converted = try GameConverter.convert(
        executable: executable, installName: "@rpath/factorio.dylib", redirectedSymbols: GameLibrary.redirectedSymbols
    )
    try converted.manifest.writeJSON(to: paths.slotManifest)
    try converted.data.write(to: paths.convertedLibrary, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("factorios-convert: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
