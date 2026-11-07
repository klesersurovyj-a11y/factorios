public import Foundation

/// A Mach-O version number, `major.minor.patch`.
public struct MachOVersion: Sendable, Equatable {
    /// The major version, up to 65535.
    public var major: UInt32
    /// The minor version, up to 255.
    public var minor: UInt32
    /// The patch version, up to 255.
    public var patch: UInt32

    /// Creates `major.minor.patch`.
    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// The `xxxx.yy.zz` nibble encoding load commands use.
    var encoded: UInt32 {
        (major & 0xFFFF) << 16 | (minor & 0xFF) << 8 | patch & 0xFF
    }
}

/// What the converter produces besides the platform retag.
public struct ConversionOptions: Sendable {
    /// The library's `LC_ID_DYLIB` name, for example `@rpath/factorio.dylib`.
    public var installName: String
    /// The `LC_BUILD_VERSION` minimum iOS version.
    public var minimumOS = MachOVersion(major: 17, minor: 0, patch: 0)
    /// The `LC_BUILD_VERSION` SDK version.
    public var sdk = MachOVersion(major: 18, minor: 0, patch: 0)
    /// Mach-O symbol names (with the leading `_`) whose pointer slots the manifest records.
    public var redirectedSymbols: Set<String>

    /// Creates options with iOS 17.0 as minimum and the 18.0 SDK.
    public init(installName: String, redirectedSymbols: Set<String>) {
        self.installName = installName
        self.redirectedSymbols = redirectedSymbols
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

/// The game executable turned into an unsigned iOS library.
public struct ConvertedImage: Sendable {
    /// A thin arm64 `MH_DYLIB` without code signature, with header room for `LC_CODE_SIGNATURE`.
    public let data: Data
    /// The pointer slots of the redirected symbols.
    public let manifest: SymbolSlotManifest

    /// Pairs a converted library with its manifest.
    public init(data: Data, manifest: SymbolSlotManifest) {
        self.data = data
        self.manifest = manifest
    }
}
