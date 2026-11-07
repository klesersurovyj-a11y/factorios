public import Foundation

/// A bzip2 decoder (Apple's Compression framework has none), used for the `0x80000006` chunks of disk images.
public enum BZip2 {
    private static let streamMagic: UInt32 = 0x42_5A_68  // "BZh"
    private static let blockMagic: UInt64 = 0x3141_5926_5359
    private static let endMagic: UInt64 = 0x1772_4538_5090

    /// Decompresses one or more concatenated bzip2 streams whose output is exactly `expectedSize` bytes.
    ///
    /// Every block's CRC and every stream's combined CRC are checked.
    public static func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw DiskImageError.corruptChunk("negative bzip2 output size") }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = try data.withUnsafeBytes { input in
            try output.withUnsafeMutableBufferPointer { buffer in
                var reader = MSBBitReader(bytes: input)
                var writer = BZip2Writer(buffer: buffer)
                repeat {
                    try decodeStream(&reader, writer: &writer)
                } while startsAnotherStream(reader)
                return writer.count
            }
        }
        guard written == expectedSize else {
            throw DiskImageError.corruptChunk("bzip2 output is \(written) bytes, expected \(expectedSize)")
        }
        return Data(output)
    }

    private static func decodeStream(_ reader: inout MSBBitReader, writer: inout BZip2Writer) throws {
        guard try reader.read(24) == streamMagic else { throw DiskImageError.corruptChunk("not bzip2 data") }
        let level = Int(try reader.read(8)) - 0x30
        guard (1...9).contains(level) else { throw DiskImageError.corruptChunk("bad bzip2 block size") }
        var tt = [UInt32](repeating: 0, count: level * 100_000)
        var combinedCRC: UInt32 = 0
        while true {
            let magic = UInt64(try reader.read(24)) << 24 | UInt64(try reader.read(24))
            let storedCRC = try reader.read(32)
            if magic == endMagic {
                guard storedCRC == combinedCRC else { throw DiskImageError.corruptChunk("bzip2 stream CRC mismatch") }
                reader.alignToByte()
                return
            }
            guard magic == blockMagic else { throw DiskImageError.corruptChunk("bad bzip2 block header") }
            let blockCRC = try tt.withUnsafeMutableBufferPointer { tt in
                let block = try BZip2Block.decode(&reader, into: tt)
                return try writer.write(block, tt: tt)
            }
            guard blockCRC == storedCRC else { throw DiskImageError.corruptChunk("bzip2 block CRC mismatch") }
            combinedCRC = (combinedCRC << 1 | combinedCRC >> 31) ^ blockCRC
        }
    }

    private static func startsAnotherStream(_ reader: MSBBitReader) -> Bool {
        var probe = reader
        probe.refill()
        return probe.remainingBytes >= 4 && probe.peek(24) == streamMagic
    }
}

/// The last stages of bzip2 decoding: inverse Burrows-Wheeler transform, then the initial run-length coding
/// (four equal bytes followed by a repeat count), with the block CRC computed over the output.
private struct BZip2Writer {
    /// CRC-32 with the polynomial 0x04C11DB7, most significant bit first, as bzip2 uses it.
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index) << 24
        for _ in 0..<8 {
            value = value & 0x8000_0000 != 0 ? value << 1 ^ 0x04C1_1DB7 : value << 1
        }
        return value
    }

    let buffer: UnsafeMutableBufferPointer<UInt8>
    private(set) var count = 0

    init(buffer: UnsafeMutableBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    /// Writes the block's original bytes and returns their CRC.
    mutating func write(_ block: BZip2Block.Decoded, tt: UnsafeMutableBufferPointer<UInt32>) throws -> UInt32 {
        Self.linkRotations(block, tt: tt)
        let table = Self.crcTable
        var crc: UInt32 = 0xFFFF_FFFF
        var position = Int(tt[block.origin] >> 8)
        var previous = -1
        var run = 0
        for _ in 0..<block.length {
            let entry = tt[position]
            position = Int(entry >> 8)
            let byte = Int(entry & 0xFF)
            if run == 4 {
                try emit(UInt8(previous), times: byte, crc: &crc, table: table)
                run = 0
                previous = -1
                continue
            }
            if byte == previous {
                run += 1
            } else {
                previous = byte
                run = 1
            }
            try emit(UInt8(byte), times: 1, crc: &crc, table: table)
        }
        return ~crc
    }

    /// Stores in the upper 24 bits of each entry the index of the entry that follows it in the original order.
    private static func linkRotations(_ block: BZip2Block.Decoded, tt: UnsafeMutableBufferPointer<UInt32>) {
        var next = [Int](repeating: 0, count: 256)
        var sum = 0
        for byte in 0..<256 {
            next[byte] = sum
            sum += block.byteCounts[byte]
        }
        for index in 0..<block.length {
            let byte = Int(tt[index] & 0xFF)
            tt[next[byte]] |= UInt32(index) << 8
            next[byte] += 1
        }
    }

    private mutating func emit(_ byte: UInt8, times: Int, crc: inout UInt32, table: [UInt32]) throws {
        guard times <= buffer.count - count else {
            throw DiskImageError.corruptChunk("bzip2 output is larger than expected")
        }
        for index in count..<(count + times) {
            buffer[index] = byte
            crc = crc << 8 ^ table[Int(crc >> 24 ^ UInt32(byte))]
        }
        count += times
    }
}
