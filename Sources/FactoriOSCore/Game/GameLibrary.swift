public import Foundation

/// The converted game library FactoriOS loads, built the same way on the device and on a development Mac.
public enum GameLibrary {
    /// The converted library's install name (LC_ID_DYLIB).
    public static let installName = "@rpath/factorio.dylib"
    /// The code-signing identifier of the converted library.
    public static let signingIdentifier = "factorio"

    /// The symbols whose pointer slots the converter records and the compatibility layer fills in.
    ///
    /// Must name exactly the entries of `FOSCompatReplacements`; the runtime checks this when it reads that table.
    public static let redirectedSymbols: Set<String> = [
        "_NSApp",
        "_OBJC_CLASS_$_NSAppleEventManager",
        "_OBJC_CLASS_$_NSBitmapImageRep",
        "_OBJC_CLASS_$_NSColorSpace",
        "_OBJC_CLASS_$_NSWorkspace",
        "_UAZoomEnabled",
        "_IOPMAssertionCreateWithDescription",
        "_IOPMAssertionRelease",
        "_clGetPlatformIDs",
        "_clGetDeviceIDs",
        "_clGetDeviceInfo",
        "_MTLCopyAllDevices",
        "_MTLCopyAllDevicesWithObserver",
        "_MTLRemoveDeviceObserver",
        "_execv",
        "_fork",
        "__NSGetExecutablePath",
    ]

    /// Converts the imported executable into an unsigned iOS library, recording the redirected symbols' slots.
    ///
    /// Slow (the executable is over 200 MB); call it off the main thread.
    public static func convert(paths: GamePaths) throws -> ConvertedImage {
        let executable = try Data(contentsOf: paths.gameExecutable, options: .alwaysMapped)
        let options = ConversionOptions(installName: installName, redirectedSymbols: redirectedSymbols)
        return try GameConverter.convert(executable: executable, options: options)
    }

    /// Writes `library` and its slot manifest, replacing earlier ones.
    ///
    /// The manifest goes first: a library without its manifest can't start, and the installation only counts as ready
    /// when both exist.
    public static func write(library: Data, manifest: SymbolSlotManifest, paths: GamePaths) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try FileManager.default.createDirectory(
            at: paths.convertedLibrary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try manifestData.write(to: paths.slotManifest, options: .atomic)
        try library.write(to: paths.convertedLibrary, options: .atomic)
    }

    /// Whether the app bundle contains the library and manifest that a device build embedded.
    public static func isBundled(paths: GamePaths) -> Bool {
        guard let library = paths.bundledLibrary, let manifest = paths.bundledSlotManifest else {
            return false
        }
        let files = FileManager.default
        return files.fileExists(atPath: library.path) && files.fileExists(atPath: manifest.path)
    }
}
