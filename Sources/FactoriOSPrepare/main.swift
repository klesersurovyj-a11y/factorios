// Prepares the game on a development Mac: imports the disk image, converts the executable and signs the library with
// the Mac's keychain identity, producing the Game and Converted folders the device build embeds and installs. The
// device needs neither the .dmg nor a .p12.
//
// Usage: factorios-prepare --dmg <factorio_mac.dmg> --output <directory> --identity <codesign identity>

import FactoriOSCore
import Foundation
import os

/// A failure to report to the developer, then exit.
struct PrepareError: Error, CustomStringConvertible {
    let description: String
}

/// The command-line options.
struct Options {
    let dmg: URL
    let output: URL
    let identity: String

    init(arguments: [String]) throws {
        var values: [String: String] = [:]
        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            guard ["--dmg", "--output", "--identity"].contains(flag), let value = remaining.popFirst() else {
                throw PrepareError(description: "usage: factorios-prepare --dmg PATH --output DIR --identity IDENTITY")
            }
            values[flag] = value
        }
        guard let dmgPath = values["--dmg"], let outputPath = values["--output"], let name = values["--identity"] else {
            throw PrepareError(description: "usage: factorios-prepare --dmg PATH --output DIR --identity IDENTITY")
        }
        dmg = URL(fileURLWithPath: dmgPath)
        output = URL(fileURLWithPath: outputPath, isDirectory: true)
        identity = name
    }
}

/// Which disk image the imported game came from, so an unchanged image isn't decompressed again.
struct SourceStamp: Codable, Equatable {
    let path: String
    let size: UInt64
    let modified: Int

    init(dmg: URL) throws {
        let values = try dmg.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        path = dmg.standardizedFileURL.path
        size = UInt64(values.fileSize ?? 0)
        modified = Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0)
    }

    /// The stamp saved at `url`, if there is a readable one.
    static func saved(at url: URL) -> Self? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}

/// Imports the game unless the same disk image was already imported into `paths`.
func importIfNeeded(dmg: URL, paths: GamePaths, stampURL: URL) throws -> ImportedGame {
    let stamp = try SourceStamp(dmg: dmg)
    if let game = GameImporter.installedGame(paths: paths), SourceStamp.saved(at: stampURL) == stamp {
        print("Factorio \(game.version) already imported from \(dmg.lastPathComponent)")
        return game
    }
    print("Importing \(dmg.lastPathComponent)")
    let lastPercent = OSAllocatedUnfairLock(initialState: -1)
    let game = try GameImporter.importGame(from: dmg, paths: paths) { progress in
        let total = max(progress.bytesTotal, 1)
        let percent = Int(min(progress.bytesDone, total) * 100 / total)
        let isNew = lastPercent.withLock { last in
            guard percent / 10 != last / 10 else {
                return false
            }
            last = percent
            return true
        }
        if isNew {
            print("  \(percent)%")
        }
    }
    try JSONEncoder().encode(stamp).write(to: stampURL, options: .atomic)
    return game
}

/// Signs the converted library with `identity` from the Mac's keychain.
func sign(library: URL, identity: String) throws {
    let codesign = Process()
    codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    codesign.arguments = [
        "--force", "--sign", identity, "--identifier", GameLibrary.signingIdentifier, "--timestamp=none", library.path,
    ]
    try codesign.run()
    codesign.waitUntilExit()
    guard codesign.terminationStatus == 0 else {
        throw PrepareError(description: "codesign failed with status \(codesign.terminationStatus)")
    }
}

do {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    let paths = GamePaths(support: options.output, documents: FileManager.default.temporaryDirectory)
    let stampURL = options.output.deletingLastPathComponent()
        .appendingPathComponent(options.output.lastPathComponent + ".source.json")
    let game = try importIfNeeded(dmg: options.dmg, paths: paths, stampURL: stampURL)
    print("Converting Factorio \(game.version)\(game.isDemo ? " (demo)" : "")")
    let converted = try GameLibrary.convert(paths: paths)
    try GameLibrary.write(library: converted.data, manifest: converted.manifest, paths: paths)
    print("Signing \(paths.convertedLibrary.lastPathComponent)")
    try sign(library: paths.convertedLibrary, identity: options.identity)
    print("Ready: \(options.output.path)")
} catch {
    FileHandle.standardError.write(Data("factorios-prepare: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
