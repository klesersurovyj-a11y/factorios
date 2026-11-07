import Foundation

/// The parts of a thin arm64 Mach-O header the signer reads and edits.
struct MachOSignatureLayout {
    /// A segment load command and the file range it maps.
    struct Segment {
        /// Offset of the `segment_command_64` from the start of the file.
        let commandOffset: Int
        let fileOffset: UInt64
        let fileSize: UInt64
    }

    /// An existing LC_CODE_SIGNATURE.
    struct ExistingSignature {
        /// Offset of the `linkedit_data_command` from the start of the file.
        let commandOffset: Int
        let dataOffset: Int
    }

    static let headerSize = 32
    static let signatureCommandSize = 16
    static let magic64: UInt32 = 0xfeed_facf
    static let cpuTypeARM64: UInt32 = 0x0100_000c
    static let segmentCommand64: UInt32 = 0x19
    static let codeSignatureCommand: UInt32 = 0x1d
    static let segmentCommandSize = 72
    static let sectionSize = 80
    static let linkeditPageSize: UInt64 = 0x4000

    let commandCount: UInt32
    let commandsSize: UInt32
    let text: Segment
    let linkedit: Segment
    let existingSignature: ExistingSignature?
    /// Where the first section's contents start: the load commands may grow up to here.
    let firstContentOffset: Int

    /// Where the signed code ends before re-signing: the old signature's start, or the end of the file.
    func codeEnd(imageSize: Int) -> Int {
        existingSignature?.dataOffset ?? imageSize
    }

    /// Reads the header and load commands of `image`.
    static func parse(_ image: Data) throws -> Self {
        try image.withUnsafeBytes { bytes in
            guard bytes.count >= headerSize, bytes.littleEndianUInt32(at: 0) == magic64,
                bytes.littleEndianUInt32(at: 4) == cpuTypeARM64
            else {
                throw SigningError.notArm64MachO
            }
            let count = bytes.littleEndianUInt32(at: 16)
            let size = bytes.littleEndianUInt32(at: 20)
            let commandsEnd = headerSize + Int(size)
            guard commandsEnd <= bytes.count else {
                throw SigningError.malformedLoadCommands
            }
            var scan = CommandScan()
            var offset = headerSize
            for _ in 0..<count {
                guard offset + 8 <= commandsEnd else {
                    throw SigningError.malformedLoadCommands
                }
                let command = bytes.littleEndianUInt32(at: offset)
                let commandSize = Int(bytes.littleEndianUInt32(at: offset + 4))
                guard commandSize >= 8, offset + commandSize <= commandsEnd else {
                    throw SigningError.malformedLoadCommands
                }
                try scan.record(command, at: offset, size: commandSize, in: bytes)
                offset += commandSize
            }
            return try Self(commandCount: count, commandsSize: size, scan: scan, imageSize: bytes.count)
        }
    }

    private init(commandCount: UInt32, commandsSize: UInt32, scan: CommandScan, imageSize: Int) throws {
        guard let textSegment = scan.segments["__TEXT"] else {
            throw SigningError.missingSegment("__TEXT")
        }
        guard let linkeditSegment = scan.segments["__LINKEDIT"] else {
            throw SigningError.missingSegment("__LINKEDIT")
        }
        let otherSegmentsEnd =
            scan.segments
            .filter { $0.key != "__LINKEDIT" }
            .map { $0.value.fileOffset + $0.value.fileSize }
            .max() ?? 0
        guard otherSegmentsEnd <= linkeditSegment.fileOffset else {
            throw SigningError.linkeditNotLast
        }
        guard linkeditSegment.fileOffset <= UInt64(imageSize) else {
            throw SigningError.malformedLoadCommands
        }
        if let signature = scan.signature {
            guard signature.dataOffset <= imageSize, UInt64(signature.dataOffset) >= linkeditSegment.fileOffset else {
                throw SigningError.malformedExistingSignature
            }
        }
        guard let firstContent = scan.firstSectionOffset ?? scan.firstSegmentContentOffset else {
            throw SigningError.malformedLoadCommands
        }
        self.commandCount = commandCount
        self.commandsSize = commandsSize
        self.text = textSegment
        self.linkedit = linkeditSegment
        self.existingSignature = scan.signature
        self.firstContentOffset = Int(clamping: firstContent)
    }

    /// Points LC_CODE_SIGNATURE (reused, or inserted into the header padding) at the signature and grows
    /// `__LINKEDIT` to end with it.
    ///
    /// - Parameters:
    ///   - image: The image, already cut or padded to `dataOffset`; only its header is changed.
    ///   - dataOffset: Where the signature starts in the file.
    ///   - dataSize: The bytes reserved for the signature.
    /// - Throws: `SigningError.noRoomForSignatureCommand` when a new command doesn't fit in the header padding.
    func writeSignatureCommand(into image: inout Data, dataOffset: Int, dataSize: Int) throws {
        let commandOffset: Int
        if let existing = existingSignature {
            commandOffset = existing.commandOffset
        } else {
            commandOffset = Self.headerSize + Int(commandsSize)
            guard commandOffset + Self.signatureCommandSize <= firstContentOffset else {
                throw SigningError.noRoomForSignatureCommand
            }
        }
        let linkeditSize = UInt64(dataOffset + dataSize) - linkedit.fileOffset
        let pageMask = Self.linkeditPageSize - 1
        let linkeditVMSize = (linkeditSize + pageMask) & ~pageMask
        let isNewCommand = existingSignature == nil
        image.withUnsafeMutableBytes { bytes in
            if isNewCommand {
                bytes.storeLittleEndian(commandCount + 1, at: 16)
                bytes.storeLittleEndian(commandsSize + UInt32(Self.signatureCommandSize), at: 20)
                bytes.storeLittleEndian(Self.codeSignatureCommand, at: commandOffset)
                bytes.storeLittleEndian(UInt32(Self.signatureCommandSize), at: commandOffset + 4)
            }
            bytes.storeLittleEndian(UInt32(dataOffset), at: commandOffset + 8)
            bytes.storeLittleEndian(UInt32(dataSize), at: commandOffset + 12)
            bytes.storeLittleEndian(linkeditVMSize, at: linkedit.commandOffset + 32)
            bytes.storeLittleEndian(linkeditSize, at: linkedit.commandOffset + 48)
        }
    }
}

/// What a pass over the load commands found.
private struct CommandScan {
    var segments: [String: MachOSignatureLayout.Segment] = [:]
    var signature: MachOSignatureLayout.ExistingSignature?
    var firstSectionOffset: UInt64?
    var firstSegmentContentOffset: UInt64?

    mutating func record(_ command: UInt32, at offset: Int, size: Int, in bytes: UnsafeRawBufferPointer) throws {
        switch command {
        case MachOSignatureLayout.segmentCommand64:
            try recordSegment(at: offset, size: size, in: bytes)
        case MachOSignatureLayout.codeSignatureCommand:
            guard size >= MachOSignatureLayout.signatureCommandSize else {
                throw SigningError.malformedLoadCommands
            }
            signature = .init(commandOffset: offset, dataOffset: Int(bytes.littleEndianUInt32(at: offset + 8)))
        default:
            // Every other load command is left as it is; signing doesn't depend on it.
            break
        }
    }

    private mutating func recordSegment(at offset: Int, size: Int, in bytes: UnsafeRawBufferPointer) throws {
        let sectionCount = Int(bytes.littleEndianUInt32(at: offset + 64))
        let segmentSize = MachOSignatureLayout.segmentCommandSize
        guard size >= segmentSize + sectionCount * MachOSignatureLayout.sectionSize else {
            throw SigningError.malformedLoadCommands
        }
        let nameBytes = UnsafeRawBufferPointer(rebasing: bytes[(offset + 8)..<(offset + 24)])
        let name = String(bytes: nameBytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        let segment = MachOSignatureLayout.Segment(
            commandOffset: offset,
            fileOffset: bytes.littleEndianUInt64(at: offset + 40),
            fileSize: bytes.littleEndianUInt64(at: offset + 48)
        )
        segments[name] = segment
        if segment.fileOffset > 0, segment.fileSize > 0 {
            firstSegmentContentOffset = min(firstSegmentContentOffset ?? segment.fileOffset, segment.fileOffset)
        }
        for index in 0..<sectionCount {
            let sectionFileOffset = UInt64(
                bytes.littleEndianUInt32(at: offset + segmentSize + index * MachOSignatureLayout.sectionSize + 48)
            )
            // Zero-fill sections have no file contents and record offset 0.
            if sectionFileOffset > 0 {
                firstSectionOffset = min(firstSectionOffset ?? sectionFileOffset, sectionFileOffset)
            }
        }
    }
}

private extension UnsafeRawBufferPointer {
    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(littleEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    func littleEndianUInt64(at offset: Int) -> UInt64 {
        UInt64(littleEndian: loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }
}

private extension UnsafeMutableRawBufferPointer {
    func storeLittleEndian<Value: FixedWidthInteger>(_ value: Value, at offset: Int) {
        storeBytes(of: value.littleEndian, toByteOffset: offset, as: Value.self)
    }
}
