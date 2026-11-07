import Foundation

/// A partition of a UDIF image as plain bytes: chunks are decoded when read, and the most recently used decoded
/// chunks are kept so that sequential and B-tree reads don't decode the same chunk again.
final class UDIFPartitionSource: RandomAccessSource {
    let size: UInt64
    private let image: any RandomAccessSource
    private let chunks: [UDIFChunk]
    private let cache = DecodedChunkCache(capacity: 16)

    init(image: any RandomAccessSource, partition: UDIFPartition) {
        self.image = image
        chunks = partition.chunks
        size = partition.sectorCount * UInt64(UDIFLayout.sectorSize)
    }

    func read(at offset: UInt64, count: Int) throws -> Data {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else { throw DiskImageError.truncated }
        var result = Data()
        result.reserveCapacity(count)
        var position = offset
        let end = offset + UInt64(count)
        while position < end {
            position += try append(from: position, upTo: end, to: &result)
        }
        return result
    }

    /// Appends the bytes from `position` to the end of the chunk (or gap) holding it, at most up to `end`;
    /// returns the number of bytes appended.
    private func append(from position: UInt64, upTo end: UInt64, to result: inout Data) throws -> UInt64 {
        let sector = position / UInt64(UDIFLayout.sectorSize)
        guard let index = chunkIndex(containing: sector) else {
            let nextStart = nextChunkStart(after: sector).map { $0 * UInt64(UDIFLayout.sectorSize) } ?? size
            let length = min(end, nextStart) - position
            result.append(Data(count: Int(length)))
            return length
        }
        let chunk = chunks[index]
        let within = position - chunk.firstSector * UInt64(UDIFLayout.sectorSize)
        let length = min(end - position, chunk.byteCount - within)
        switch chunk.type {
        case UDIFChunk.Kind.zeroFill, UDIFChunk.Kind.ignore:
            result.append(Data(count: Int(length)))
        case UDIFChunk.Kind.raw:
            guard within + length <= chunk.storedLength else {
                throw DiskImageError.malformedImage("a raw chunk is shorter than its sectors")
            }
            result.append(try image.read(at: chunk.storedOffset + within, count: Int(length)))
        default:
            let decoded = try cache.value(for: index) { try decode(chunk) }
            result.append(decoded[Int(within)..<Int(within + length)])
        }
        return length
    }

    private func decode(_ chunk: UDIFChunk) throws -> Data {
        guard chunk.type == UDIFChunk.Kind.zlib || chunk.type == UDIFChunk.Kind.bzip2 else {
            throw DiskImageError.unsupportedChunk(chunk.type)
        }
        guard chunk.storedLength <= UInt64(Int.max), chunk.byteCount <= UInt64(Int.max) else {
            throw DiskImageError.malformedImage("a chunk is too large")
        }
        let stored = try image.read(at: chunk.storedOffset, count: Int(chunk.storedLength))
        if chunk.type == UDIFChunk.Kind.zlib {
            return try Inflate.decompressZlib(stored, expectedSize: Int(chunk.byteCount))
        }
        return try BZip2.decompress(stored, expectedSize: Int(chunk.byteCount))
    }

    /// The index of the chunk whose sectors include `sector`, if any.
    private func chunkIndex(containing sector: UInt64) -> Int? {
        var low = 0
        var high = chunks.count
        while low < high {
            let middle = (low + high) / 2
            if chunks[middle].firstSector <= sector {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        return index >= 0 && sector < chunks[index].firstSector + chunks[index].sectorCount ? index : nil
    }

    private func nextChunkStart(after sector: UInt64) -> UInt64? {
        chunks.first { $0.firstSector > sector }?.firstSector
    }
}

/// A small least-recently-used cache of decoded chunks, shared by every reader of one partition source.
///
/// `@unchecked Sendable`: all state is guarded by `lock` (FactoriOS supports iOS 17, before `Mutex`).
private final class DecodedChunkCache: @unchecked Sendable {
    private let lock = NSLock()
    private let capacity: Int
    private var entries: [Int: Data] = [:]
    /// Chunk indices, least recently used first.
    private var order: [Int] = []

    init(capacity: Int) {
        self.capacity = capacity
    }

    /// The cached decoded chunk, or the result of `decode`, which runs outside the lock.
    func value(for index: Int, decode: () throws -> Data) throws -> Data {
        if let cached = lookup(index) {
            return cached
        }
        let decoded = try decode()
        lock.withLock {
            if entries[index] == nil {
                entries[index] = decoded
                order.append(index)
            }
            while order.count > capacity {
                entries[order.removeFirst()] = nil
            }
        }
        return decoded
    }

    private func lookup(_ index: Int) -> Data? {
        lock.withLock {
            let data = entries[index]
            if data != nil, let position = order.firstIndex(of: index) {
                order.remove(at: position)
                order.append(index)
            }
            return data
        }
    }
}
