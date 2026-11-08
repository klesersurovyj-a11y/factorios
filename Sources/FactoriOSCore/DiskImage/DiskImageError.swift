public import Foundation

/// Why reading the game's disk image, or importing the game from it, failed.
public enum DiskImageError: Error, LocalizedError, Equatable {
    /// The file could not be opened or read: its name and the reason.
    case unreadable(String)
    /// The file has no UDIF `koly` trailer: it is not a macOS disk image.
    case notUDIF
    /// The image's trailer, property list or block tables are inconsistent.
    case malformedImage(String)
    /// A data structure ends before its declared size.
    case truncated
    /// A chunk uses a compression scheme FactoriOS does not decode (ADC, LZFSE, LZMA).
    case unsupportedChunk(UInt32)
    /// A compressed chunk failed to decode.
    case corruptChunk(String)
    /// The image has no `Apple_HFS` partition.
    case noHFSPartition
    /// The partition does not hold an HFS+ or HFSX volume.
    case notHFSPlus
    /// The volume's B-trees or records are inconsistent.
    case malformedVolume(String)
    /// The item at this path is not a directory.
    case notADirectory(String)
    /// The file is stored with HFS+ (decmpfs) compression, which FactoriOS does not decode.
    case compressedFile(String)
    /// Writing an extracted item failed: its name and the reason.
    case writeFailed(String)
    /// The volume holds no `factorio.app`.
    case gameNotFound
    /// The extracted app has no `Contents/MacOS/factorio`.
    case missingExecutable
    /// The game's version could not be read from `Contents/data/base/info.json`.
    case unreadableVersion

    /// A sentence the prepare tool prints.
    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            "Couldn't read \(detail)"
        case .notUDIF:
            "This file isn't a macOS disk image (.dmg)."
        case .malformedImage(let detail):
            "The disk image is damaged: \(detail)"
        case .truncated:
            "The disk image is damaged: a structure ends early."
        case .unsupportedChunk(let type):
            "The disk image uses an unsupported compression (chunk type 0x\(String(type, radix: 16)))."
        case .corruptChunk(let detail):
            "The disk image is damaged: \(detail)"
        case .noHFSPartition:
            "The disk image has no Mac (HFS+) partition."
        case .notHFSPlus:
            "The disk image's partition isn't an HFS+ volume."
        case .malformedVolume(let detail):
            "The disk image's volume is damaged: \(detail)"
        default:
            itemDescription
        }
    }

    private var itemDescription: String {
        switch self {
        case .notADirectory(let path):
            "\(path) isn't a folder."
        case .compressedFile(let path):
            "\(path) is stored compressed in a way FactoriOS can't read."
        case .writeFailed(let detail):
            "Couldn't write \(detail)"
        case .gameNotFound:
            "The disk image doesn't contain factorio.app. Download the macOS version from factorio.com."
        case .missingExecutable:
            "factorio.app in the disk image has no game executable."
        case .unreadableVersion:
            "Couldn't read the game's version from factorio.app."
        default:
            "The disk image couldn't be read."
        }
    }
}

/// How far an extraction has got.
public struct ExtractionProgress: Sendable, Equatable {
    /// Bytes of file contents written so far.
    public let bytesDone: UInt64
    /// Bytes of file contents the extraction writes in total.
    public let bytesTotal: UInt64

    /// Creates a progress report.
    public init(bytesDone: UInt64, bytesTotal: UInt64) {
        self.bytesDone = bytesDone
        self.bytesTotal = bytesTotal
    }
}
