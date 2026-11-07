/// One load command, kept byte for byte so commands the converter doesn't touch are copied unchanged.
struct RawLoadCommand {
    /// `cmd`.
    let type: UInt32
    /// The whole command, `cmdsize` bytes.
    let bytes: [UInt8]
}

/// An `LC_SEGMENT_64`.
struct Segment {
    let name: String
    let vmAddress: UInt64
    let vmSize: UInt64
    let fileOffset: UInt64
    let fileSize: UInt64
    /// Lowest file offset of a section that has file contents (zero-fill sections have none).
    let firstSectionOffset: UInt64?
}

/// A library the image links against (`LC_LOAD_DYLIB` and relatives), in ordinal order.
struct LinkedLibrary {
    let type: UInt32
    let path: String
    let timestamp: UInt32
    let currentVersion: UInt32
    let compatibilityVersion: UInt32
}

/// The bind streams of `LC_DYLD_INFO(_ONLY)`, as file offsets in the image.
struct DyldInfoStreams {
    let bind: Range<UInt64>
    let lazyBind: Range<UInt64>
}

/// The `mach_header_64` and load commands of a thin 64-bit Mach-O.
struct LoadCommandTable {
    private(set) var cpuType: UInt32 = 0
    private(set) var fileType: UInt32 = 0
    private(set) var flags: UInt32 = 0
    /// `sizeofcmds` of the original table.
    private(set) var commandsSize = 0
    private(set) var commands: [RawLoadCommand] = []
    private(set) var segments: [Segment] = []
    private(set) var libraries: [LinkedLibrary] = []
    private(set) var dyldInfo: DyldInfoStreams?
    /// File range of the old code signature (`LC_CODE_SIGNATURE` dataoff/datasize).
    private(set) var codeSignature: Range<UInt64>?
    /// End of the furthest `__LINKEDIT` data other than the code signature.
    private(set) var linkeditDataEnd: UInt64 = 0
    private(set) var usesChainedFixups = false

    /// Parses `header`: the image's first `32 + sizeofcmds` bytes.
    init(header: [UInt8]) throws {
        guard try header.uint32LE(at: 0) == MachO.magic64 else {
            throw MachOError.notMachO
        }
        cpuType = try header.uint32LE(at: 4)
        fileType = try header.uint32LE(at: 12)
        let commandCount = try header.uint32LE(at: 16)
        commandsSize = Int(try header.uint32LE(at: 20))
        flags = try header.uint32LE(at: 24)
        guard MachO.headerSize + commandsSize <= header.count else {
            throw MachOError.malformed("the load commands run past the end of the file")
        }
        var offset = MachO.headerSize
        let end = MachO.headerSize + commandsSize
        for _ in 0..<commandCount {
            let type = try header.uint32LE(at: offset)
            let size = Int(try header.uint32LE(at: offset + 4))
            guard size >= 8, size.isMultiple(of: 4), size <= end - offset else {
                throw MachOError.malformed("load command at \(offset) has size \(size)")
            }
            let command = RawLoadCommand(type: type, bytes: Array(header[offset..<offset + size]))
            try record(command)
            commands.append(command)
            offset += size
        }
    }

    /// The segment called `name`.
    func segment(named name: String) -> Segment? {
        segments.first { $0.name == name }
    }

    /// Lowest file offset of any section: where the header padding ends.
    var firstSectionOffset: UInt64? {
        segments.compactMap(\.firstSectionOffset).min()
    }

    private mutating func record(_ command: RawLoadCommand) throws {
        let bytes = command.bytes
        switch command.type {
        case LoadCommandType.segment64:
            segments.append(try Self.parseSegment(bytes))
        case let type where LoadCommandType.libraryReferences.contains(type):
            libraries.append(try Self.parseLibrary(bytes))
        case LoadCommandType.dyldInfo, LoadCommandType.dyldInfoOnly:
            try recordDyldInfo(bytes)
        case LoadCommandType.symtab:
            try extendLinkedit(bytes, offsetAt: 8, countAt: 12, entrySize: 16)
            try extendLinkedit(bytes, offsetAt: 16, countAt: 20, entrySize: 1)
        case LoadCommandType.dysymtab:
            let tables: [(offsetAt: Int, entrySize: UInt64)] = [(32, 8), (40, 56), (48, 4), (56, 4), (64, 8), (72, 8)]
            for (offsetAt, entrySize) in tables {
                try extendLinkedit(bytes, offsetAt: offsetAt, countAt: offsetAt + 4, entrySize: entrySize)
            }
        case LoadCommandType.codeSignature:
            let start = UInt64(try bytes.uint32LE(at: 8))
            codeSignature = start..<start + UInt64(try bytes.uint32LE(at: 12))
        case let type where LoadCommandType.linkeditData.contains(type):
            usesChainedFixups = usesChainedFixups || type == LoadCommandType.dyldChainedFixups
            try extendLinkedit(bytes, offsetAt: 8, countAt: 12, entrySize: 1)
        default:
            break
        }
    }

    private mutating func recordDyldInfo(_ bytes: [UInt8]) throws {
        for offsetAt in stride(from: 8, through: 40, by: 8) {
            try extendLinkedit(bytes, offsetAt: offsetAt, countAt: offsetAt + 4, entrySize: 1)
        }
        let bindStart = UInt64(try bytes.uint32LE(at: 16))
        let bindSize = UInt64(try bytes.uint32LE(at: 20))
        let lazyStart = UInt64(try bytes.uint32LE(at: 32))
        let lazySize = UInt64(try bytes.uint32LE(at: 36))
        dyldInfo = DyldInfoStreams(bind: bindStart..<bindStart + bindSize, lazyBind: lazyStart..<lazyStart + lazySize)
    }

    /// Pushes `linkeditDataEnd` past a table described by a file offset and an entry count.
    private mutating func extendLinkedit(_ bytes: [UInt8], offsetAt: Int, countAt: Int, entrySize: UInt64) throws {
        let start = UInt64(try bytes.uint32LE(at: offsetAt))
        let length = UInt64(try bytes.uint32LE(at: countAt)) * entrySize
        if length > 0 {
            linkeditDataEnd = Swift.max(linkeditDataEnd, start + length)
        }
    }

    private static func parseSegment(_ bytes: [UInt8]) throws -> Segment {
        let sectionCount = Int(try bytes.uint32LE(at: 64))
        guard 72 + sectionCount * 80 <= bytes.count else {
            throw MachOError.malformed("a segment's sections run past its load command")
        }
        var firstSection: UInt64?
        for index in 0..<sectionCount {
            let sectionOffset = UInt64(try bytes.uint32LE(at: 72 + index * 80 + 48))
            if sectionOffset != 0 {
                firstSection = Swift.min(firstSection ?? sectionOffset, sectionOffset)
            }
        }
        return Segment(
            name: try bytes.cString(in: 8..<24),
            vmAddress: try bytes.uint64LE(at: 24),
            vmSize: try bytes.uint64LE(at: 32),
            fileOffset: try bytes.uint64LE(at: 40),
            fileSize: try bytes.uint64LE(at: 48),
            firstSectionOffset: firstSection
        )
    }

    private static func parseLibrary(_ bytes: [UInt8]) throws -> LinkedLibrary {
        let nameOffset = Int(try bytes.uint32LE(at: 8))
        guard nameOffset >= 24, nameOffset < bytes.count else {
            throw MachOError.malformed("a library command's name lies outside it")
        }
        return LinkedLibrary(
            type: try bytes.uint32LE(at: 0),
            path: try bytes.cString(in: nameOffset..<bytes.count),
            timestamp: try bytes.uint32LE(at: 12),
            currentVersion: try bytes.uint32LE(at: 16),
            compatibilityVersion: try bytes.uint32LE(at: 20)
        )
    }
}
