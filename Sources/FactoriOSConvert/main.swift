// Converts the imported game's macOS executable into the unsigned iOS library and slot manifest the app build
// embeds. `prepare` imports the game before; `deploy` and `simulator:build` sign the library after.
//
// Usage: factorios-convert device|simulator <directory>, which holds Game/factorio.app; writes Converted/.

import FactoriOSCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

guard arguments.count == 2, let platform = TargetPlatform(rawValue: arguments[0]) else {
    let platforms = TargetPlatform.allCases.map(\.rawValue).joined(separator: "|")
    FileHandle.standardError.write(Data("usage: factorios-convert \(platforms) DIRECTORY\n".utf8))
    exit(EXIT_FAILURE)
}

let directory = arguments[1]

let paths = GamePaths(
    support: URL(fileURLWithPath: directory, isDirectory: true),
    documents: FileManager.default.temporaryDirectory
)

do {
    // Mapped, not read: the executable is over 200 MB.
    let executable = try Data(contentsOf: paths.gameExecutable, options: .alwaysMapped)
    let converted = try GameConverter.convert(
        executable: executable,
        platform: platform,
        installName: "@rpath/factorio.dylib",
        redirectedSymbols: GameLibrary.redirectedSymbols
    )
    try converted.manifest.writeJSON(to: paths.slotManifest)
    try converted.data.write(to: paths.convertedLibrary, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("factorios-convert: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
