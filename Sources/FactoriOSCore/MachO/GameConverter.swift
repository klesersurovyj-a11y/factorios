public import Foundation

/// Turns Factorio's macOS executable into an iOS library that `dlopen` can load once it is signed.
public enum GameConverter {
    /// Header bytes left free after the load commands: room for the signer's `LC_CODE_SIGNATURE`.
    static let signatureCommandRoom = 16

    /// Converts the arm64 slice of `executable`: retags it for iOS, makes it an `MH_DYLIB`, flattens framework
    /// paths, weak-links the libraries iOS lacks or trims (and weak-imports their symbols), weak-imports every
    /// redirected symbol so a missing one doesn't stop `dlopen`, drops the old code signature and records the pointer
    /// slots of `options.redirectedSymbols`.
    public static func convert(executable: Data, options: ConversionOptions) throws -> ConvertedImage {
        let slice = try FatBinary.arm64Slice(of: executable)
        let start = executable.startIndex
        var image = Data(executable[start + slice.lowerBound..<start + slice.upperBound])
        let table = try readTable(of: image)
        let streams = try validate(table)
        guard let text = table.segment(named: "__TEXT") else {
            throw MachOError.missingSegment("__TEXT")
        }
        let libraries = table.libraries.map(ConvertedLibrary.init)
        var walker = BindStreamWalker(
            segments: table.segments,
            libraries: libraries,
            redirectedSymbols: options.redirectedSymbols,
            imageBase: text.vmAddress
        )
        try image.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) throws in
            try walker.walk(buffer, range: streams.bind, stream: .bind)
            try walker.walk(buffer, range: streams.lazyBind, stream: .lazyBind)
        }
        let linkeditSize = try removeSignature(from: &image, table: table)
        let rewriter = LoadCommandRewriter(
            table: table,
            libraries: libraries,
            options: options,
            textVMAddress: text.vmAddress,
            linkeditSize: linkeditSize
        )
        let (commands, count) = try rewriter.build()
        try install(commands, count: count, table: table, into: &image)
        let slots = walker.slots.mapValues { Array(Set($0)).sorted() }
        return ConvertedImage(data: image, manifest: SymbolSlotManifest(slots: slots))
    }

    private static func readTable(of image: Data) throws -> LoadCommandTable {
        guard image.count >= MachO.headerSize else {
            throw MachOError.notMachO
        }
        let commandsSize = Int(try [UInt8](image.prefix(MachO.headerSize)).uint32LE(at: 20))
        guard commandsSize <= image.count - MachO.headerSize else {
            throw MachOError.malformed("the load commands run past the end of the file")
        }
        return try LoadCommandTable(header: [UInt8](image.prefix(MachO.headerSize + commandsSize)))
    }

    /// Checks the image is something this converter handles and returns its bind streams.
    private static func validate(_ table: LoadCommandTable) throws -> DyldInfoStreams {
        guard table.cpuType == MachO.cpuTypeARM64 else {
            throw MachOError.wrongArchitecture(cpuType: table.cpuType)
        }
        guard table.fileType == MachO.fileTypeExecute else {
            throw MachOError.unsupportedFileType(table.fileType)
        }
        guard !table.usesChainedFixups else {
            throw MachOError.chainedFixupsUnsupported
        }
        guard let streams = table.dyldInfo else {
            throw MachOError.malformed("the executable has no LC_DYLD_INFO bind information")
        }
        return streams
    }

    /// Truncates the file at the old signature and returns `__LINKEDIT`'s new sizes; `nil` if it was unsigned.
    private static func removeSignature(
        from image: inout Data, table: LoadCommandTable
    ) throws -> LoadCommandRewriter.LinkeditSize? {
        guard let signature = table.codeSignature else {
            // An unsigned executable keeps its __LINKEDIT as it is.
            return nil
        }
        guard let linkedit = table.segment(named: "__LINKEDIT") else {
            throw MachOError.missingSegment("__LINKEDIT")
        }
        let cut = signature.lowerBound
        guard cut >= linkedit.fileOffset, table.linkeditDataEnd <= cut, cut <= UInt64(image.count) else {
            throw MachOError.signatureNotAtEnd
        }
        image.removeSubrange(Int(cut)..<image.count)
        let fileSize = cut - linkedit.fileOffset
        let vmSize = (fileSize + MachO.pageSize - 1) & ~(MachO.pageSize - 1)
        return LoadCommandRewriter.LinkeditSize(fileSize: fileSize, vmSize: vmSize)
    }

    /// Writes the new header fields and load commands, zeroing what is left of the old table.
    private static func install(
        _ commands: [UInt8],
        count: UInt32,
        table: LoadCommandTable,
        into image: inout Data
    ) throws {
        guard let firstSection = table.firstSectionOffset, firstSection <= UInt64(image.count) else {
            throw MachOError.malformed("the executable has no section with file contents")
        }
        let available = Int(firstSection) - MachO.headerSize
        let needed = commands.count + signatureCommandRoom
        guard needed <= available else {
            throw MachOError.noRoomForLoadCommands(needed: needed, available: available)
        }
        let flags = (table.flags | MachO.flagNoReexportedDylibs) & ~MachO.flagPIE
        image.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            buffer.storeBytes(of: MachO.fileTypeDylib.littleEndian, toByteOffset: 12, as: UInt32.self)
            buffer.storeBytes(of: count.littleEndian, toByteOffset: 16, as: UInt32.self)
            buffer.storeBytes(of: UInt32(commands.count).littleEndian, toByteOffset: 20, as: UInt32.self)
            buffer.storeBytes(of: flags.littleEndian, toByteOffset: 24, as: UInt32.self)
            let tableStart = MachO.headerSize
            let tableEnd = tableStart + commands.count
            UnsafeMutableRawBufferPointer(rebasing: buffer[tableStart..<tableEnd]).copyBytes(from: commands)
            for index in tableEnd..<max(tableEnd, tableStart + table.commandsSize) {
                buffer[index] = 0
            }
        }
    }
}
