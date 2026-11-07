import Foundation

/// A file, folder or symbolic link of an HFS+ volume, with hard links already resolved to their target.
public struct HFSItem: Sendable, Equatable {
    /// What an item is.
    public enum Kind: Sendable, Equatable {
        /// A folder.
        case directory
        /// A regular file.
        case file
        /// A symbolic link; its data fork holds the target path.
        case symlink
    }

    /// The name, precomposed (NFC), with HFS+'s `/` shown as `:` as macOS does.
    public let name: String
    /// The path from the volume root, `/`-separated, without a leading `/`; empty for the root.
    public let path: String
    /// What the item is.
    public let kind: Kind
    /// The data fork's size in bytes; 0 for folders.
    public let size: UInt64
    /// The BSD permission bits (`mode & 0o7777`).
    public let mode: UInt16
    /// Catalog node ID: the folder ID for folders, the file ID (of the hard link's target) for files.
    let id: UInt32
    /// The data fork, overflow extents included.
    let fork: HFSFork
    /// Whether the file is stored with decmpfs compression (`UF_COMPRESSED`).
    let isCompressed: Bool
}

/// A contiguous run of allocation blocks.
struct HFSExtent: Sendable, Equatable {
    let startBlock: UInt32
    let blockCount: UInt32
}

/// An `HFSPlusForkData`: a fork's size and the extents that hold it.
struct HFSFork: Sendable, Equatable {
    static let empty = Self(logicalSize: 0, totalBlocks: 0, extents: [])

    let logicalSize: UInt64
    let totalBlocks: UInt32
    var extents: [HFSExtent]

    /// The number of allocation blocks the known extents cover.
    var coveredBlocks: UInt64 {
        extents.reduce(0) { $0 + UInt64($1.blockCount) }
    }
}

extension HFSFork {
    /// Parses the 80-byte fork data record at `offset`.
    init(data: Data, at offset: Int) throws {
        logicalSize = try data.diskUInt64(at: offset)
        totalBlocks = try data.diskUInt32(at: offset + 12)
        extents = try HFSExtent.list(in: data, at: offset + 16)
    }
}

extension HFSExtent {
    /// The non-empty extents of an 8-entry `HFSPlusExtentRecord`.
    static func list(in data: Data, at offset: Int) throws -> [Self] {
        var extents = [Self]()
        for index in 0..<8 {
            let extent = Self(
                startBlock: try data.diskUInt32(at: offset + 8 * index),
                blockCount: try data.diskUInt32(at: offset + 8 * index + 4)
            )
            if extent.blockCount > 0 {
                extents.append(extent)
            }
        }
        return extents
    }
}

/// Reads forks from the volume's allocation blocks.
struct HFSStorage: Sendable {
    let source: any RandomAccessSource
    let blockSize: UInt64

    /// Reads `count` bytes at logical `offset` of `fork`, across extents.
    func read(_ fork: HFSFork, at offset: UInt64, count: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var position = offset
        var remaining = UInt64(count)
        var extentStart: UInt64 = 0
        for extent in fork.extents where remaining > 0 {
            let extentLength = UInt64(extent.blockCount) * blockSize
            if position < extentStart + extentLength {
                let within = position - extentStart
                let length = min(remaining, extentLength - within)
                result.append(try source.read(at: UInt64(extent.startBlock) * blockSize + within, count: Int(length)))
                position += length
                remaining -= length
            }
            extentStart += extentLength
        }
        guard remaining == 0 else { throw DiskImageError.malformedVolume("a read runs past the end of a fork") }
        return result
    }

    /// Passes the fork's `logicalSize` bytes to `body` in order, in pieces of at most `maximumPieceSize` bytes.
    func forEachPiece(of fork: HFSFork, maximumPieceSize: Int, _ body: (Data) throws -> Void) throws {
        var remaining = fork.logicalSize
        for extent in fork.extents where remaining > 0 {
            var offset = UInt64(extent.startBlock) * blockSize
            var extentRemaining = min(remaining, UInt64(extent.blockCount) * blockSize)
            remaining -= extentRemaining
            while extentRemaining > 0 {
                let length = min(extentRemaining, UInt64(maximumPieceSize))
                try body(try source.read(at: offset, count: Int(length)))
                offset += length
                extentRemaining -= length
            }
        }
        guard remaining == 0 else { throw DiskImageError.malformedVolume("a fork is shorter than its size") }
    }
}

/// The fields of a catalog folder or file record that FactoriOS uses.
struct CatalogEntry: Sendable {
    /// A hard link: a file record that stands for an `iNode<n>` file or a `dir_<n>` folder.
    enum Link {
        case file(UInt32)
        case directory(UInt32)
    }

    private enum Code {
        static let hardLinkType: UInt32 = 0x686C_6E6B  // 'hlnk'
        static let hardLinkCreator: UInt32 = 0x6866_732B  // 'hfs+'
        static let directoryLinkType: UInt32 = 0x6664_7270  // 'fdrp'
        static let directoryLinkCreator: UInt32 = 0x4D41_4353  // 'MACS'
        static let symlinkType: UInt32 = 0x736C_6E6B  // 'slnk'
        static let symlinkCreator: UInt32 = 0x7268_6170  // 'rhap'
        static let compressedFlag: UInt8 = 0x20  // UF_COMPRESSED
        static let fileTypeMask: UInt16 = 0o170_000
        static let symlinkMode: UInt16 = 0o120_000
    }

    let isFolder: Bool
    let id: UInt32
    private let fileMode: UInt16
    private let ownerFlags: UInt8
    private let special: UInt32
    private let fileType: UInt32
    private let creator: UInt32
    let dataFork: HFSFork

    /// Parses an `HFSPlusCatalogFolder` (type 1) or `HFSPlusCatalogFile` (type 2) record.
    init(_ value: Data) throws {
        switch try value.diskUInt16(at: 0) {
        case 1:
            isFolder = true
        case 2:
            isFolder = false
        default:
            throw DiskImageError.malformedVolume("a catalog record is neither a folder nor a file")
        }
        id = try value.diskUInt32(at: 8)
        ownerFlags = try value.diskUInt8(at: 41)
        fileMode = try value.diskUInt16(at: 42)
        special = try value.diskUInt32(at: 44)
        fileType = try isFolder ? 0 : value.diskUInt32(at: 48)
        creator = try isFolder ? 0 : value.diskUInt32(at: 52)
        dataFork = try isFolder ? .empty : HFSFork(data: value, at: 88)
    }

    /// The hard link this record stands for; `special` holds the link's node number.
    var link: Link? {
        if fileType == Code.hardLinkType, creator == Code.hardLinkCreator {
            return .file(special)
        }
        if fileType == Code.directoryLinkType, creator == Code.directoryLinkCreator {
            return .directory(special)
        }
        return nil
    }

    var isSymlink: Bool {
        (fileType == Code.symlinkType && creator == Code.symlinkCreator)
            || fileMode & Code.fileTypeMask == Code.symlinkMode
    }

    var isCompressed: Bool { ownerFlags & Code.compressedFlag != 0 }

    /// Permission bits; a mode of 0 means the BSD information was never set, which macOS shows as 755 / 644.
    var permissions: UInt16 {
        guard fileMode != 0 else { return isFolder ? 0o755 : 0o644 }
        return fileMode & 0o7777
    }
}

/// Catalog names: big-endian UTF-16, decomposed, compared case-insensitively on HFS+ and binary on HFSX.
enum HFSName {
    /// The private folder holding hard-linked files (`iNode<n>`).
    static let fileLinkDirectory: [UInt16] = [0, 0, 0, 0] + Array("HFS+ Private Data".utf16)
    /// The private folder holding hard-linked folders (`dir_<n>`).
    static let directoryLinkDirectory = Array(".HFS+ Private Directory Data\r".utf16)
    /// Metadata at the volume root that macOS never shows.
    static let hiddenAtRoot: Set<[UInt16]> = [
        fileLinkDirectory, directoryLinkDirectory, Array(".journal".utf16), Array(".journal_info_block".utf16),
    ]

    /// The name as macOS shows it: precomposed, with `/` (legal in HFS+ names) as `:`.
    static func string(_ units: [UInt16]) -> String {
        String(decoding: units, as: UTF16.self).precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "/", with: ":")
    }

    /// Whether `name` sorts before or equal to `other` in the catalog.
    ///
    /// Case-insensitive volumes fold ASCII only, which is exact for the private folders' `iNode<n>` / `dir_<n>`
    /// names this is used for.
    static func isOrdered(_ name: [UInt16], atMost other: [UInt16], binary: Bool) -> Bool {
        if binary {
            return !other.lexicographicallyPrecedes(name)
        }
        return !other.lazy.map(foldASCII).lexicographicallyPrecedes(name.lazy.map(foldASCII))
    }

    private static func foldASCII(_ unit: UInt16) -> UInt16 {
        (0x41...0x5A).contains(unit) ? unit + 0x20 : unit
    }
}
