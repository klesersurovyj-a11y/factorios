import Foundation

/// The converted game library FactoriOS loads, which the Mac converter builds.
public enum GameLibrary {
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

    /// Whether the app bundle contains the library and manifest that a device build embedded.
    public static func isBundled(paths: GamePaths) -> Bool {
        guard let library = paths.bundledLibrary, let manifest = paths.bundledSlotManifest else {
            return false
        }
        let files = FileManager.default
        return files.fileExists(atPath: library.path) && files.fileExists(atPath: manifest.path)
    }
}

/// Where the converted image holds pointers to symbols the compatibility layer replaces.
public struct SymbolSlotManifest: Codable, Sendable, Equatable {
    /// Symbol → offsets of 8-byte pointer slots from the image's `mach_header` (slot vmaddr − `__TEXT` vmaddr),
    /// ascending and without duplicates.
    public let slots: [String: [UInt64]]

    /// Creates a manifest from symbol → slot offsets.
    public init(slots: [String: [UInt64]]) {
        self.slots = slots
    }
}
