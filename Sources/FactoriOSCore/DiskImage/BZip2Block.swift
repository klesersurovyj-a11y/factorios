/// The first stage of a bzip2 block: its tables, then Huffman-coded MTF/RLE2 symbols, decoded into the
/// Burrows-Wheeler-transformed bytes.
enum BZip2Block {
    /// A block after Huffman, move-to-front and run-length (RUNA/RUNB) decoding.
    struct Decoded {
        /// Bytes in the transformed block.
        let length: Int
        /// Row of the original string in the sorted rotations (`origPtr`).
        let origin: Int
        /// How often each byte value occurs in the block.
        let byteCounts: [Int]
    }

    /// Symbols per selector group.
    private static let groupSize = 50

    /// Decodes the block that follows the block magic and CRC; the bytes go into the low 8 bits of `tt`.
    static func decode(_ reader: inout MSBBitReader, into tt: UnsafeMutableBufferPointer<UInt32>) throws -> Decoded {
        guard try !reader.readBit() else { throw DiskImageError.corruptChunk("randomised bzip2 blocks are obsolete") }
        let origin = Int(try reader.read(24))
        let symbols = try readSymbolMap(&reader)
        let groupCount = Int(try reader.read(3))
        guard (2...6).contains(groupCount) else { throw DiskImageError.corruptChunk("bad bzip2 table count") }
        let selectorCount = Int(try reader.read(15))
        guard selectorCount > 0 else { throw DiskImageError.corruptChunk("bzip2 block without selectors") }
        let selectors = try readSelectors(&reader, count: selectorCount, groupCount: groupCount)
        var tables = [BZip2Huffman]()
        for _ in 0..<groupCount {
            tables.append(try BZip2Huffman(lengths: readCodeLengths(&reader, alphabetSize: symbols.count + 2)))
        }
        var sink = SymbolSink(tt: tt, symbols: symbols)
        try readSymbols(&reader, tables: tables, selectors: selectors, sink: &sink)
        guard origin < sink.length else { throw DiskImageError.corruptChunk("bzip2 origin pointer out of range") }
        return Decoded(length: sink.length, origin: origin, byteCounts: sink.byteCounts)
    }

    /// The byte values in use, in order: a 16-bit map of used 16-value ranges, then a 16-bit map per used range.
    private static func readSymbolMap(_ reader: inout MSBBitReader) throws -> [UInt8] {
        let ranges = try reader.read(16)
        var symbols = [UInt8]()
        for range in 0..<16 where ranges & (0x8000 >> range) != 0 {
            let values = try reader.read(16)
            for value in 0..<16 where values & (0x8000 >> value) != 0 {
                symbols.append(UInt8(range * 16 + value))
            }
        }
        guard !symbols.isEmpty else { throw DiskImageError.corruptChunk("bzip2 block uses no symbols") }
        return symbols
    }

    /// Which table codes each group of 50 symbols: unary-coded, move-to-front transformed table numbers.
    private static func readSelectors(_ reader: inout MSBBitReader, count: Int, groupCount: Int) throws -> [UInt8] {
        var order = (0..<groupCount).map { UInt8($0) }
        var selectors = [UInt8]()
        selectors.reserveCapacity(count)
        for _ in 0..<count {
            var index = 0
            while try reader.readBit() {
                index += 1
                guard index < groupCount else { throw DiskImageError.corruptChunk("bad bzip2 selector") }
            }
            let table = order.remove(at: index)
            order.insert(table, at: 0)
            selectors.append(table)
        }
        return selectors
    }

    /// Delta-coded code lengths: a 5-bit start, then per symbol `1x` steps (x = 0: +1, x = 1: -1) ended by `0`.
    private static func readCodeLengths(_ reader: inout MSBBitReader, alphabetSize: Int) throws -> [UInt8] {
        var length = Int(try reader.read(5))
        var lengths = [UInt8]()
        lengths.reserveCapacity(alphabetSize)
        for _ in 0..<alphabetSize {
            while true {
                guard (1...BZip2Huffman.maximumLength).contains(length) else {
                    throw DiskImageError.corruptChunk("bad bzip2 code length")
                }
                guard try reader.readBit() else { break }
                length += try reader.readBit() ? -1 : 1
            }
            lengths.append(UInt8(length))
        }
        return lengths
    }

    private static func readSymbols(
        _ reader: inout MSBBitReader,
        tables: [BZip2Huffman],
        selectors: [UInt8],
        sink: inout SymbolSink
    ) throws {
        let endOfBlock = sink.symbols.count + 1
        var selectorIndex = 0
        var remainingInGroup = 0
        var table = tables[0]
        while true {
            if remainingInGroup == 0 {
                guard selectorIndex < selectors.count, Int(selectors[selectorIndex]) < tables.count else {
                    throw DiskImageError.corruptChunk("bzip2 block runs past its selectors")
                }
                table = tables[Int(selectors[selectorIndex])]
                selectorIndex += 1
                remainingInGroup = groupSize
            }
            remainingInGroup -= 1
            let symbol = try table.decode(&reader)
            if symbol <= 1 {
                try sink.addRun(symbol)
                continue
            }
            if sink.hasPendingRun {
                try sink.flushRun()
            }
            guard symbol != endOfBlock else { break }
            try sink.addMoveToFront(index: symbol - 1)
        }
    }
}

/// Undoes RUNA/RUNB run lengths and move-to-front coding, writing bytes into `tt`.
private struct SymbolSink {
    let tt: UnsafeMutableBufferPointer<UInt32>
    let symbols: [UInt8]
    var length = 0
    var byteCounts = [Int](repeating: 0, count: 256)
    private var moveToFront: [UInt8] = (0...255).map { UInt8($0) }
    private var runLength = 0
    private var runWeight = 1

    init(tt: UnsafeMutableBufferPointer<UInt32>, symbols: [UInt8]) {
        self.tt = tt
        self.symbols = symbols
    }

    /// RUNA (0) adds 1 × weight, RUNB (1) adds 2 × weight; the weight doubles with each run symbol.
    mutating func addRun(_ symbol: Int) throws {
        runLength += runWeight << symbol
        runWeight <<= 1
        guard runLength <= tt.count - length else { throw DiskImageError.corruptChunk("bzip2 block too long") }
    }

    /// Whether RUNA/RUNB symbols are waiting for `flushRun`.
    var hasPendingRun: Bool { runLength > 0 }

    /// Writes the pending run of the front byte.
    mutating func flushRun() throws {
        let byte = symbols[Int(moveToFront[0])]
        guard runLength <= tt.count - length else { throw DiskImageError.corruptChunk("bzip2 block too long") }
        for index in length..<(length + runLength) {
            tt[index] = UInt32(byte)
        }
        byteCounts[Int(byte)] += runLength
        length += runLength
        runLength = 0
        runWeight = 1
    }

    /// Moves the entry at `index` to the front and writes its byte.
    mutating func addMoveToFront(index: Int) throws {
        guard index < symbols.count, length < tt.count else {
            throw DiskImageError.corruptChunk("bad bzip2 symbol")
        }
        let value = moveToFront[index]
        var position = index
        while position > 0 {
            moveToFront[position] = moveToFront[position - 1]
            position -= 1
        }
        moveToFront[0] = value
        let byte = symbols[Int(value)]
        tt[length] = UInt32(byte)
        byteCounts[Int(byte)] += 1
        length += 1
    }
}

/// One of a bzip2 block's canonical Huffman codes (lengths 1...20, read most-significant bit first).
struct BZip2Huffman {
    static let maximumLength = 20
    /// Codes up to this long decode with one table lookup.
    private static let fastBits = 10

    /// Indexed by the next `fastBits` bits: `symbol << 5 | length`, or 0 for codes longer than `fastBits`.
    private var fast: [UInt16]
    /// Per length: the first code, the number of codes, and where their symbols start in `sorted`.
    private var firstCode = [UInt32](repeating: 0, count: maximumLength + 1)
    private var codeCount = [UInt32](repeating: 0, count: maximumLength + 1)
    private var firstIndex = [Int](repeating: 0, count: maximumLength + 1)
    /// Symbols ordered by code length, then value.
    private var sorted: [UInt16]
    private var longest = 0

    init(lengths: [UInt8]) throws {
        fast = [UInt16](repeating: 0, count: 1 << Self.fastBits)
        sorted = [UInt16](repeating: 0, count: lengths.count)
        for length in lengths {
            codeCount[Int(length)] += 1
            longest = max(longest, Int(length))
        }
        var next = 0
        var code: UInt32 = 0
        for length in 1...Self.maximumLength {
            firstIndex[length] = next
            firstCode[length] = code
            next += Int(codeCount[length])
            code += codeCount[length]
            guard code <= 1 << length else { throw DiskImageError.corruptChunk("over-subscribed bzip2 code") }
            code <<= 1
        }
        var position = firstIndex
        for (symbol, length) in lengths.enumerated() {
            sorted[position[Int(length)]] = UInt16(symbol)
            position[Int(length)] += 1
        }
        fillFastTable()
    }

    private mutating func fillFastTable() {
        for length in 1...min(Self.fastBits, longest) {
            let span = 1 << (Self.fastBits - length)
            for offset in 0..<Int(codeCount[length]) {
                let symbol = sorted[firstIndex[length] + offset]
                let start = (Int(firstCode[length]) + offset) * span
                let entry = symbol << 5 | UInt16(length)
                for index in start..<(start + span) {
                    fast[index] = entry
                }
            }
        }
    }

    /// Decodes one symbol.
    func decode(_ reader: inout MSBBitReader) throws -> Int {
        reader.refill()
        let window = reader.peek(Self.maximumLength)
        let entry = fast[Int(window >> UInt32(Self.maximumLength - Self.fastBits))]
        if entry != 0 {
            try reader.skip(Int(entry & 31))
            return Int(entry >> 5)
        }
        var length = Self.fastBits + 1
        while length <= longest {
            let code = window >> UInt32(Self.maximumLength - length)
            if code >= firstCode[length], code - firstCode[length] < codeCount[length] {
                try reader.skip(length)
                return Int(sorted[firstIndex[length] + Int(code - firstCode[length])])
            }
            length += 1
        }
        throw DiskImageError.corruptChunk("invalid bzip2 code")
    }
}
