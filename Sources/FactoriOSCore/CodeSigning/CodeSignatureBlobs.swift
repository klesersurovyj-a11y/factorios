import Crypto
import Foundation

/// Builds the blobs of an embedded code signature (Apple's `cs_blobs.h` layout, big-endian).
enum CodeSignatureBlobs {
    static let superBlobMagic: UInt32 = 0xfade_0cc0
    static let requirementsMagic: UInt32 = 0xfade_0c01
    static let entitlementsMagic: UInt32 = 0xfade_7171
    static let derEntitlementsMagic: UInt32 = 0xfade_7172
    static let cmsWrapperMagic: UInt32 = 0xfade_0b01

    /// Slot types used in the SuperBlob index and as CodeDirectory special slot numbers.
    enum Slot {
        static let codeDirectory: UInt32 = 0
        static let requirements: UInt32 = 2
        static let entitlements: UInt32 = 5
        static let derEntitlements: UInt32 = 7
        static let cmsSignature: UInt32 = 0x10000
    }

    /// One blob of a SuperBlob and its slot type.
    struct Entry {
        let slot: UInt32
        let blob: [UInt8]
    }

    /// Size of the magic and length fields that start every blob.
    static let blobHeaderSize = 8
    /// Size of the SuperBlob header (magic, length, count).
    static let superBlobHeaderSize = 12
    /// Size of one SuperBlob index entry (type, offset).
    static let indexEntrySize = 8

    /// An empty requirement set: a requirements SuperBlob with no entries.
    static let emptyRequirements: [UInt8] = {
        var writer = SignatureBlobWriter(capacity: superBlobHeaderSize)
        writer.append(bigEndian: requirementsMagic)
        writer.append(bigEndian: UInt32(superBlobHeaderSize))
        writer.append(bigEndian: UInt32(0))
        return writer.bytes
    }()

    /// Wraps `payload` in a generic blob: magic, total length, payload.
    static func blob(magic: UInt32, payload: some Collection<UInt8>) -> [UInt8] {
        let length = blobHeaderSize + payload.count
        var writer = SignatureBlobWriter(capacity: length)
        writer.append(bigEndian: magic)
        writer.append(bigEndian: UInt32(length))
        writer.append(contentsOf: payload)
        return writer.bytes
    }

    /// The size of a SuperBlob holding blobs of these sizes.
    static func superBlobSize(blobSizes: [Int]) -> Int {
        superBlobHeaderSize + blobSizes.count * indexEntrySize + blobSizes.reduce(0, +)
    }

    /// Packs `entries` into the embedded-signature SuperBlob, in the given order.
    static func superBlob(_ entries: [Entry]) -> [UInt8] {
        let length = superBlobSize(blobSizes: entries.map(\.blob.count))
        var writer = SignatureBlobWriter(capacity: length)
        writer.append(bigEndian: superBlobMagic)
        writer.append(bigEndian: UInt32(length))
        writer.append(bigEndian: UInt32(entries.count))
        var offset = superBlobHeaderSize + entries.count * indexEntrySize
        for entry in entries {
            writer.append(bigEndian: entry.slot)
            writer.append(bigEndian: UInt32(offset))
            offset += entry.blob.count
        }
        for entry in entries {
            writer.append(contentsOf: entry.blob)
        }
        return writer.bytes
    }

    /// SHA-256 of `bytes`.
    static func sha256(_ bytes: some DataProtocol) -> [UInt8] {
        Array(SHA256.hash(data: bytes))
    }
}

/// A version 0x20400 CodeDirectory with SHA-256 page hashes.
struct CodeDirectory {
    static let magic: UInt32 = 0xfade_0c02
    static let version: UInt32 = 0x20400
    /// Size of the fixed fields up to and including `execSegFlags`.
    static let headerSize = 88
    static let hashSize = 32
    static let hashTypeSHA256: UInt8 = 2
    static let pageSizeLog2: UInt8 = 12
    static let pageSize = 1 << 12

    let identifier: String
    let teamIdentifier: String
    /// Hashes of the special slots, starting with slot -1 (Info.plist); a missing item is all zeros.
    let specialSlotHashes: [[UInt8]]
    /// `__TEXT` file offset.
    let executableSegmentBase: UInt64
    /// `__TEXT` file size.
    let executableSegmentLimit: UInt64

    /// The encoded size for code ending at `codeLimit`.
    func size(codeLimit: Int) -> Int {
        hashOffset + Self.pageCount(codeLimit: codeLimit) * Self.hashSize
    }

    private var identifierOffset: Int { Self.headerSize }
    private var teamOffset: Int { identifierOffset + identifier.utf8.count + 1 }
    private var hashOffset: Int {
        teamOffset + teamIdentifier.utf8.count + 1 + specialSlotHashes.count * Self.hashSize
    }

    private static func pageCount(codeLimit: Int) -> Int {
        (codeLimit + pageSize - 1) / pageSize
    }

    /// Encodes the CodeDirectory, hashing every 4 KiB page of `code` up to `codeLimit` (the last page partial).
    ///
    /// `codeLimit` must fit in 32 bits; the 64-bit code limit field is then left zero, as Apple does.
    func encode(code: Data, codeLimit: Int) -> [UInt8] {
        let pageCount = Self.pageCount(codeLimit: codeLimit)
        let length = size(codeLimit: codeLimit)
        var writer = SignatureBlobWriter(capacity: length)
        writer.append(bigEndian: Self.magic)
        writer.append(bigEndian: UInt32(length))
        writer.append(bigEndian: Self.version)
        writer.append(bigEndian: UInt32(0))  // flags
        writer.append(bigEndian: UInt32(hashOffset))
        writer.append(bigEndian: UInt32(identifierOffset))
        writer.append(bigEndian: UInt32(specialSlotHashes.count))
        writer.append(bigEndian: UInt32(pageCount))
        writer.append(bigEndian: UInt32(codeLimit))
        writer.append(bigEndian: UInt8(Self.hashSize))
        writer.append(bigEndian: Self.hashTypeSHA256)
        writer.append(bigEndian: UInt8(0))  // platform
        writer.append(bigEndian: Self.pageSizeLog2)
        writer.append(bigEndian: UInt32(0))  // spare2
        writer.append(bigEndian: UInt32(0))  // scatterOffset
        writer.append(bigEndian: UInt32(teamOffset))
        writer.append(bigEndian: UInt32(0))  // spare3
        writer.append(bigEndian: UInt64(0))  // codeLimit64
        writer.append(bigEndian: executableSegmentBase)
        writer.append(bigEndian: executableSegmentLimit)
        writer.append(bigEndian: UInt64(0))  // execSegFlags
        writer.appendCString(identifier)
        writer.appendCString(teamIdentifier)
        for hash in specialSlotHashes.reversed() {
            writer.append(contentsOf: hash)
        }
        code.withUnsafeBytes { bytes in
            for page in 0..<pageCount {
                let start = page * Self.pageSize
                let end = min(start + Self.pageSize, codeLimit)
                var hasher = SHA256()
                hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: bytes[start..<end]))
                writer.append(contentsOf: hasher.finalize())
            }
        }
        return writer.bytes
    }
}

/// Appends big-endian fields to a growing blob.
struct SignatureBlobWriter {
    private(set) var bytes: [UInt8] = []

    init(capacity: Int) {
        bytes.reserveCapacity(capacity)
    }

    mutating func append<Value: FixedWidthInteger>(bigEndian value: Value) {
        withUnsafeBytes(of: value.bigEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func append(contentsOf other: some Sequence<UInt8>) {
        bytes.append(contentsOf: other)
    }

    /// Appends the UTF-8 bytes of `string` and a terminating NUL.
    mutating func appendCString(_ string: String) {
        bytes.append(contentsOf: string.utf8)
        bytes.append(0)
    }
}
