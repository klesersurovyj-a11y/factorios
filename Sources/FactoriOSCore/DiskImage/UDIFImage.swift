import Foundation

/// A UDIF disk image (`.dmg`): a `koly` trailer pointing at an XML property list whose `blkx` tables describe how
/// each partition's sectors are stored (zero-filled, raw or compressed chunks).
public struct UDIFImage: Sendable {
    /// The partitions in the image's block tables, in table order.
    public let partitions: [UDIFPartition]
    private let source: any RandomAccessSource

    /// Reads the trailer and block tables of the image in `source`.
    public static func open(_ source: any RandomAccessSource) throws -> Self {
        guard source.size >= UInt64(UDIFLayout.trailerSize) else { throw DiskImageError.notUDIF }
        let trailer = try source.read(at: source.size - UInt64(UDIFLayout.trailerSize), count: UDIFLayout.trailerSize)
        guard try trailer.diskUInt32(at: 0) == UDIFLayout.kolySignature else { throw DiskImageError.notUDIF }
        let dataForkOffset = try trailer.diskUInt64(at: 24)
        let plistOffset = try trailer.diskUInt64(at: 216)
        let plistLength = try trailer.diskUInt64(at: 224)
        guard plistLength > 0, plistLength <= UDIFLayout.maximumPlistLength,
            plistOffset <= source.size, plistLength <= source.size - plistOffset
        else {
            throw DiskImageError.malformedImage("the property list lies outside the file")
        }
        let plist = try source.read(at: plistOffset, count: Int(plistLength))
        let resources: ResourceList
        do {
            resources = try PropertyListDecoder().decode(ResourceList.self, from: plist)
        } catch {
            throw DiskImageError.malformedImage("unreadable property list (\(error.localizedDescription))")
        }
        let tables = try resources.resourceFork.blkx.map { entry in
            try UDIFPartition(name: entry.name ?? "", table: entry.data, dataForkOffset: dataForkOffset)
        }
        return Self(partitions: tables, source: source)
    }

    /// The partition's sectors, decoded on demand; recently decoded chunks are cached.
    public func source(for partition: UDIFPartition) -> any RandomAccessSource {
        UDIFPartitionSource(image: source, partition: partition)
    }

    /// The partition that holds the HFS+ volume (`Apple_HFS`, or `Apple_HFSX`).
    public func hfsPartition() throws -> UDIFPartition {
        guard let partition = partitions.first(where: { $0.name.contains("Apple_HFS") }) else {
            throw DiskImageError.noHFSPartition
        }
        return partition
    }
}

/// One partition of a UDIF image: an entry of the `blkx` resource and its `mish` block table.
public struct UDIFPartition: Sendable {
    /// The entry's name, such as `disk image (Apple_HFS : 5)`.
    public let name: String
    /// The partition's size in 512-byte sectors.
    public let sectorCount: UInt64
    /// The chunks that carry data, ordered by sector.
    let chunks: [UDIFChunk]

    init(name: String, table: Data, dataForkOffset: UInt64) throws {
        guard try table.diskUInt32(at: 0) == UDIFLayout.mishSignature else {
            throw DiskImageError.malformedImage("block table of \(name) has no mish signature")
        }
        self.name = name
        sectorCount = try table.diskUInt64(at: 16)
        let dataStart = dataForkOffset &+ (try table.diskUInt64(at: 24))
        let chunkCount = Int(try table.diskUInt32(at: 200))
        var entries = [UDIFChunk]()
        entries.reserveCapacity(chunkCount)
        for index in 0..<chunkCount {
            let offset = UDIFLayout.firstChunkOffset + index * UDIFLayout.chunkSize
            let entry = try table.diskBytes(at: offset, count: UDIFLayout.chunkSize)
            let chunk = try UDIFChunk(entry: entry, dataStart: dataStart)
            guard chunk.type != UDIFChunk.Kind.comment, chunk.type != UDIFChunk.Kind.terminator else { continue }
            guard chunk.firstSector <= sectorCount, chunk.sectorCount <= sectorCount - chunk.firstSector else {
                throw DiskImageError.malformedImage("a chunk of \(name) lies outside the partition")
            }
            entries.append(chunk)
        }
        chunks = entries.sorted { $0.firstSector < $1.firstSector }
    }
}

/// One entry of a `mish` block table: a run of sectors stored one way.
struct UDIFChunk: Sendable {
    /// Chunk types (`BLKXChunkEntry.EntryType`).
    enum Kind {
        static let zeroFill: UInt32 = 0x0000_0000
        static let raw: UInt32 = 0x0000_0001
        static let ignore: UInt32 = 0x0000_0002
        static let zlib: UInt32 = 0x8000_0005
        static let bzip2: UInt32 = 0x8000_0006
        static let comment: UInt32 = 0x7FFF_FFFE
        static let terminator: UInt32 = 0xFFFF_FFFF
    }

    let type: UInt32
    /// First sector, relative to the partition.
    let firstSector: UInt64
    let sectorCount: UInt64
    /// Absolute offset of the stored bytes in the image file.
    let storedOffset: UInt64
    let storedLength: UInt64

    init(entry: Data, dataStart: UInt64) throws {
        type = try entry.diskUInt32(at: 0)
        firstSector = try entry.diskUInt64(at: 8)
        sectorCount = try entry.diskUInt64(at: 16)
        storedOffset = dataStart &+ (try entry.diskUInt64(at: 24))
        storedLength = try entry.diskUInt64(at: 32)
    }

    var byteCount: UInt64 { sectorCount * UInt64(UDIFLayout.sectorSize) }
}

/// Sizes and magic numbers of the UDIF format.
enum UDIFLayout {
    static let trailerSize = 512
    static let sectorSize = 512
    static let kolySignature: UInt32 = 0x6B6F_6C79
    static let mishSignature: UInt32 = 0x6D69_7368
    static let firstChunkOffset = 204
    static let chunkSize = 40
    static let maximumPlistLength: UInt64 = 64 << 20
}

/// The parts of the image's property list that matter: `resource-fork` / `blkx` / (`Name`, `Data`).
private struct ResourceList: Decodable {
    struct ResourceFork: Decodable {
        let blkx: [Entry]
    }

    struct Entry: Decodable {
        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case data = "Data"
        }

        let name: String?
        let data: Data
    }

    enum CodingKeys: String, CodingKey {
        case resourceFork = "resource-fork"
    }

    let resourceFork: ResourceFork
}
