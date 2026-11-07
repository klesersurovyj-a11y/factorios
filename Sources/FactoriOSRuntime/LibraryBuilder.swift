import FactoriOSCore
import Foundation

/// Turns the imported macOS executable into the signed iOS library FactoriOS loads.
///
/// Slow (the executable is over 200 MB), so callers run it off the main actor.
enum LibraryBuilder {
    /// Converts the imported executable, recording the pointer slots the compatibility layer fills in.
    static func convert(paths: GamePaths) throws -> ConvertedImage {
        try GameLibrary.convert(paths: paths)
    }

    /// Signs the converted library and writes it with its slot manifest, replacing any earlier ones.
    static func sign(_ image: ConvertedImage, identity: some SigningIdentity, paths: GamePaths) throws {
        let signed = try MachOSigner.sign(image.data, identifier: GameLibrary.signingIdentifier, identity: identity)
        try GameLibrary.write(library: signed, manifest: image.manifest, paths: paths)
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
