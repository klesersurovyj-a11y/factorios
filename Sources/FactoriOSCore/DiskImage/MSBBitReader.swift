/// Reads bits most-significant first (bzip2's order) from a byte buffer.
///
/// Up to 64 bits are buffered left-aligned in `buffer`; bits past the end of the input read as zero when peeked,
/// and consuming them throws.
struct MSBBitReader {
    private let bytes: UnsafeRawBufferPointer
    private var position = 0
    private var buffer: UInt64 = 0
    private var available = 0

    init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    /// Whole bytes not yet consumed, buffered ones included.
    var remainingBytes: Int { available / 8 + bytes.count - position }

    /// Fills the buffer to at least 57 bits, or with everything left.
    mutating func refill() {
        while available <= 56, position < bytes.count {
            buffer |= UInt64(bytes[position]) &<< (56 - available)
            available += 8
            position += 1
        }
    }

    /// The next `count` (1...32) bits without consuming them; call `refill` first.
    func peek(_ count: Int) -> UInt32 {
        UInt32(truncatingIfNeeded: buffer &>> (64 - count))
    }

    /// Consumes `count` (0...32) bits that were peeked.
    mutating func skip(_ count: Int) throws {
        guard count <= available else { throw DiskImageError.corruptChunk("bzip2 data ends early") }
        buffer &<<= count
        available -= count
    }

    /// Reads `count` (1...32) bits.
    mutating func read(_ count: Int) throws -> UInt32 {
        refill()
        let value = peek(count)
        try skip(count)
        return value
    }

    /// Reads one bit.
    mutating func readBit() throws -> Bool {
        try read(1) == 1
    }

    /// Drops the bits up to the next byte boundary.
    mutating func alignToByte() {
        let extra = available % 8
        buffer &<<= extra
        available -= extra
    }
}
