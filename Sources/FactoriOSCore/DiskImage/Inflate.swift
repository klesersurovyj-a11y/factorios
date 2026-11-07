public import Foundation

/// A zlib (RFC 1950) / DEFLATE (RFC 1951) decoder for the `0x80000005` chunks of disk images.
public enum Inflate {
    /// Base lengths of length symbols 257...285.
    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227,
        258,
    ]
    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
    ]
    /// Base distances of distance symbols 0...29.
    private static let distanceBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1_025, 1_537, 2_049, 3_073,
        4_097, 6_145, 8_193, 12_289, 16_385, 24_577,
    ]
    private static let distanceExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
    ]
    /// The order in which code-length code lengths are stored in a dynamic block header.
    private static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Decompresses a zlib stream whose output is exactly `expectedSize` bytes; the Adler-32 checksum is checked.
    public static func decompressZlib(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize >= 0 else { throw DiskImageError.corruptChunk("negative zlib output size") }
        guard data.count >= 6 else { throw DiskImageError.corruptChunk("zlib data too short") }
        let method = data[data.startIndex]
        let flags = data[data.startIndex + 1]
        guard method & 0x0F == 8, (UInt16(method) << 8 | UInt16(flags)).isMultiple(of: 31), flags & 0x20 == 0 else {
            throw DiskImageError.corruptChunk("bad zlib header")
        }
        var output = [UInt8](repeating: 0, count: expectedSize)
        let checksum = try data.withUnsafeBytes { input in
            try output.withUnsafeMutableBufferPointer { buffer in
                var reader = LSBBitReader(bytes: input, startingAt: 2)
                var writer = InflateWriter(buffer: buffer)
                try inflate(&reader, writer: &writer)
                guard writer.count == expectedSize else {
                    throw DiskImageError.corruptChunk("zlib output is \(writer.count) bytes, expected \(expectedSize)")
                }
                reader.alignToByte()
                var stored: UInt32 = 0
                for _ in 0..<4 {
                    stored = stored << 8 | UInt32(try reader.readByte())
                }
                return stored
            }
        }
        guard checksum == adler32(output) else { throw DiskImageError.corruptChunk("zlib checksum mismatch") }
        return Data(output)
    }

    private static func inflate(_ reader: inout LSBBitReader, writer: inout InflateWriter) throws {
        var isLast = false
        while !isLast {
            isLast = try reader.read(1) == 1
            switch try reader.read(2) {
            case 0:
                try copyStored(&reader, writer: &writer)
            case 1:
                try decodeCodes(&reader, writer: &writer, tables: try fixedTables())
            case 2:
                try decodeCodes(&reader, writer: &writer, tables: try readDynamicTables(&reader))
            default:
                throw DiskImageError.corruptChunk("bad deflate block type")
            }
        }
    }

    private static func copyStored(_ reader: inout LSBBitReader, writer: inout InflateWriter) throws {
        reader.alignToByte()
        let length = try reader.read(16)
        let complement = try reader.read(16)
        guard length == ~complement & 0xFFFF else { throw DiskImageError.corruptChunk("bad stored block length") }
        for _ in 0..<length {
            try writer.append(try reader.readByte())
        }
    }

    private static func decodeCodes(
        _ reader: inout LSBBitReader,
        writer: inout InflateWriter,
        tables: (literals: InflateHuffman, distances: InflateHuffman)
    ) throws {
        while true {
            let symbol = try tables.literals.decode(&reader)
            if symbol < 256 {
                try writer.append(UInt8(symbol))
                continue
            }
            guard symbol != 256 else { break }
            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count else { throw DiskImageError.corruptChunk("bad deflate length") }
            let length = lengthBase[lengthIndex] + Int(try reader.read(lengthExtra[lengthIndex]))
            let distanceIndex = try tables.distances.decode(&reader)
            guard distanceIndex < distanceBase.count else { throw DiskImageError.corruptChunk("bad deflate distance") }
            let distance = distanceBase[distanceIndex] + Int(try reader.read(distanceExtra[distanceIndex]))
            try writer.copy(distance: distance, length: length)
        }
    }

    private static func fixedTables() throws -> (literals: InflateHuffman, distances: InflateHuffman) {
        var lengths = [UInt8](repeating: 8, count: 288)
        for index in 144..<256 {
            lengths[index] = 9
        }
        for index in 256..<280 {
            lengths[index] = 7
        }
        return (try InflateHuffman(lengths: lengths), try InflateHuffman(lengths: [UInt8](repeating: 5, count: 30)))
    }

    private static func readDynamicTables(
        _ reader: inout LSBBitReader
    ) throws -> (literals: InflateHuffman, distances: InflateHuffman) {
        let literalCount = Int(try reader.read(5)) + 257
        let distanceCount = Int(try reader.read(5)) + 1
        let codeLengthCount = Int(try reader.read(4)) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw DiskImageError.corruptChunk("bad deflate header") }
        var codeLengthLengths = [UInt8](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengthLengths[codeLengthOrder[index]] = UInt8(try reader.read(3))
        }
        let codeLengths = try InflateHuffman(lengths: codeLengthLengths)
        let lengths = try readCodeLengths(&reader, using: codeLengths, count: literalCount + distanceCount)
        guard lengths[256] != 0 else { throw DiskImageError.corruptChunk("deflate block without end code") }
        return (
            try InflateHuffman(lengths: Array(lengths[0..<literalCount])),
            try InflateHuffman(lengths: Array(lengths[literalCount...]))
        )
    }

    /// Literal/length and distance code lengths, run-length coded with symbols 16 (repeat previous), 17 and 18
    /// (repeat zero).
    private static func readCodeLengths(
        _ reader: inout LSBBitReader,
        using code: InflateHuffman,
        count: Int
    ) throws -> [UInt8] {
        var lengths = [UInt8]()
        lengths.reserveCapacity(count)
        while lengths.count < count {
            let symbol = try code.decode(&reader)
            let value: UInt8
            let repeats: Int
            switch symbol {
            case 0...15:
                value = UInt8(symbol)
                repeats = 1
            case 16:
                guard let last = lengths.last else {
                    throw DiskImageError.corruptChunk("deflate repeat without a length")
                }
                value = last
                repeats = 3 + Int(try reader.read(2))
            case 17:
                value = 0
                repeats = 3 + Int(try reader.read(3))
            default:
                value = 0
                repeats = 11 + Int(try reader.read(7))
            }
            guard lengths.count + repeats <= count else {
                throw DiskImageError.corruptChunk("deflate code lengths overflow")
            }
            lengths.append(contentsOf: repeatElement(value, count: repeats))
        }
        return lengths
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let modulus: UInt32 = 65_521
        var low: UInt32 = 1
        var high: UInt32 = 0
        var start = 0
        while start < bytes.count {
            // 5552 is the most bytes that can be summed before `high` could overflow 32 bits.
            let end = min(start + 5_552, bytes.count)
            for index in start..<end {
                low += UInt32(bytes[index])
                high += low
            }
            low %= modulus
            high %= modulus
            start = end
        }
        return high << 16 | low
    }
}

/// Output of an inflate run, with back-references into what was already written.
private struct InflateWriter {
    let buffer: UnsafeMutableBufferPointer<UInt8>
    private(set) var count = 0

    init(buffer: UnsafeMutableBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    mutating func append(_ byte: UInt8) throws {
        guard count < buffer.count else { throw DiskImageError.corruptChunk("zlib output is larger than expected") }
        buffer[count] = byte
        count += 1
    }

    /// Copies `length` bytes from `distance` bytes back; the ranges may overlap.
    mutating func copy(distance: Int, length: Int) throws {
        guard distance <= count else { throw DiskImageError.corruptChunk("deflate distance too far back") }
        guard length <= buffer.count - count else {
            throw DiskImageError.corruptChunk("zlib output is larger than expected")
        }
        for index in count..<(count + length) {
            buffer[index] = buffer[index - distance]
        }
        count += length
    }
}

/// A canonical DEFLATE Huffman code, decoded bit by bit (codes are stored most significant bit first).
private struct InflateHuffman {
    private static let maximumLength = 15
    /// Number of codes of each length.
    private var counts = [Int](repeating: 0, count: maximumLength + 1)
    /// Symbols ordered by code length, then value.
    private var symbols: [Int] = []

    init(lengths: [UInt8]) throws {
        for length in lengths {
            counts[Int(length)] += 1
        }
        var left = 1
        for length in 1...Self.maximumLength {
            left = left * 2 - counts[length]
            guard left >= 0 else { throw DiskImageError.corruptChunk("over-subscribed deflate code") }
        }
        var offsets = [Int](repeating: 0, count: Self.maximumLength + 1)
        for length in 1..<Self.maximumLength {
            offsets[length + 1] = offsets[length] + counts[length]
        }
        symbols = [Int](repeating: 0, count: lengths.count - counts[0])
        for (symbol, length) in lengths.enumerated() where length != 0 {
            symbols[offsets[Int(length)]] = symbol
            offsets[Int(length)] += 1
        }
    }

    func decode(_ reader: inout LSBBitReader) throws -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...Self.maximumLength {
            code |= Int(try reader.read(1))
            let count = counts[length]
            if code - first < count {
                return symbols[index + code - first]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw DiskImageError.corruptChunk("invalid deflate code")
    }
}
