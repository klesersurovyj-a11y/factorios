public import Foundation

/// Why the game's executable couldn't be turned into an iOS library.
public enum MachOError: Error, LocalizedError, Equatable {
    /// The file is neither a universal binary nor a little-endian 64-bit Mach-O.
    case notMachO
    /// The universal binary has no arm64 slice.
    case noArm64Slice
    /// The Mach-O is built for another CPU (the `cputype` field).
    case wrongArchitecture(cpuType: UInt32)
    /// The Mach-O is not a main executable (the `filetype` field).
    case unsupportedFileType(UInt32)
    /// A structure points outside the file or contradicts another one.
    case malformed(String)
    /// The executable uses `LC_DYLD_CHAINED_FIXUPS` instead of bind opcodes.
    case chainedFixupsUnsupported
    /// A bind stream uses threaded binds, which belong to chained fixups.
    case threadedBindsUnsupported
    /// A segment the conversion needs is missing.
    case missingSegment(String)
    /// `__LINKEDIT` holds data after the old code signature, so the signature can't be cut off.
    case signatureNotAtEnd
    /// The rebuilt load commands plus room for a code signature command don't fit in the header padding.
    case noRoomForLoadCommands(needed: Int, available: Int)

    /// A sentence the converter prints.
    public var errorDescription: String? {
        switch self {
        case .notMachO:
            "The game executable isn't a Mach-O file."
        case .noArm64Slice:
            "The game executable has no Apple silicon (arm64) build."
        case .wrongArchitecture(let cpuType):
            "The game executable is built for CPU type \(cpuType), not arm64."
        case .unsupportedFileType(let fileType):
            "The game executable has Mach-O file type \(fileType), not an executable."
        case .malformed(let detail):
            "The game executable is damaged: \(detail)."
        case .chainedFixupsUnsupported:
            "This Factorio build uses chained fixups, which FactoriOS can't convert yet."
        case .threadedBindsUnsupported:
            "This Factorio build uses threaded binds, which FactoriOS can't convert."
        case .missingSegment(let name):
            "The game executable has no \(name) segment."
        case .signatureNotAtEnd:
            "The game executable's code signature isn't at the end of the file."
        // swift-format wants `let` on each binding; SwiftLint's pattern_matching_keywords wants one in front.
        // swiftlint:disable:next pattern_matching_keywords
        case .noRoomForLoadCommands(let needed, let available):
            "The converted load commands need \(needed) bytes but the header has room for \(available)."
        }
    }
}
