/// Reads bits least-significant first (DEFLATE's order) from a byte buffer.
struct LSBBitReader {
    private let bytes: UnsafeRawBufferPointer
    private var position: Int
    private var buffer: UInt64 = 0
    private var available = 0

    init(bytes: UnsafeRawBufferPointer, startingAt position: Int) {
        self.bytes = bytes
        self.position = position
    }

    /// Reads `count` (0...32) bits, the first one read being the least significant.
    mutating func read(_ count: Int) throws -> UInt32 {
        guard count > 0 else { return 0 }
        while available < count {
            guard position < bytes.count else { throw DiskImageError.corruptChunk("zlib data ends early") }
            buffer |= UInt64(bytes[position]) &<< available
            available += 8
            position += 1
        }
        let value = UInt32(truncatingIfNeeded: buffer & ((1 &<< UInt64(count)) - 1))
        buffer &>>= count
        available -= count
        return value
    }

    /// Drops the bits up to the next byte boundary.
    mutating func alignToByte() {
        let extra = available % 8
        buffer &>>= extra
        available -= extra
    }

    /// Reads a whole byte; the reader must be byte-aligned.
    mutating func readByte() throws -> UInt8 {
        UInt8(truncatingIfNeeded: try read(8))
    }
}
