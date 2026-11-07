import FactoriOSCore
import Foundation

/// Turns the imported macOS executable into the signed iOS library FactoriOS loads.
///
/// Slow (the executable is over 200 MB), so callers run it off the main actor.
enum LibraryBuilder {
    /// The converted library's install name (LC_ID_DYLIB).
    static let installName = "@rpath/factorio.dylib"
    /// The code-signing identifier of the converted library.
    static let signingIdentifier = "factorio"

    /// Converts the imported executable, recording the pointer slots the compatibility layer fills in.
    static func convert(paths: GamePaths) throws -> ConvertedImage {
        let executable = try Data(contentsOf: paths.gameExecutable, options: .alwaysMapped)
        let options = ConversionOptions(installName: installName, redirectedSymbols: CompatTable.symbols())
        return try GameConverter.convert(executable: executable, options: options)
    }

    /// Signs the converted library and writes it with its slot manifest, replacing any earlier ones.
    static func sign(_ image: ConvertedImage, identity: some SigningIdentity, paths: GamePaths) throws {
        let signed = try MachOSigner.sign(image.data, identifier: signingIdentifier, identity: identity)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifest = try encoder.encode(image.manifest)
        try FileManager.default.createDirectory(
            at: paths.convertedLibrary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The manifest goes first: a library without its manifest can't start, and the installation only counts as
        // ready when both exist.
        try manifest.write(to: paths.slotManifest, options: .atomic)
        try signed.write(to: paths.convertedLibrary, options: .atomic)
    }

    /// Deletes the converted library and its manifest, if present.
    static func removeBuilt(paths: GamePaths) throws {
        for file in [paths.convertedLibrary, paths.slotManifest]
        where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Whether a converted library and its manifest are in place.
    static func isBuilt(paths: GamePaths) -> Bool {
        let files = FileManager.default
        return files.fileExists(atPath: paths.convertedLibrary.path)
            && files.fileExists(atPath: paths.slotManifest.path)
    }
}
