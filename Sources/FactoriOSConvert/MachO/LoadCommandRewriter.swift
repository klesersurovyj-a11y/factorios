/// Builds the iOS library's load-command table from the macOS executable's.
struct LoadCommandRewriter {
    /// New `__LINKEDIT` sizes once the old code signature is cut off.
    struct LinkeditSize {
        let fileSize: UInt64
        let vmSize: UInt64
    }

    let table: LoadCommandTable
    let libraries: [ConvertedLibrary]
    let platform: TargetPlatform
    let installName: String
    let textVMAddress: UInt64
    let linkeditSize: LinkeditSize?

    /// The new table (`sizeofcmds` bytes) and its command count (`ncmds`).
    func build() throws -> (commands: [UInt8], count: UInt32) {
        // LC_ID_DYLIB comes first, as dylibify and LiveContainer place it. dyld ignores the timestamp.
        var output = Self.dylibCommand(
            type: LoadCommandType.idDylib,
            path: installName,
            timestamp: 1,
            currentVersion: 0x1_0000,
            compatibilityVersion: 0x1_0000
        )
        var count: UInt32 = 1
        var libraryIndex = 0
        for command in table.commands {
            let bytes = try converted(command, libraryIndex: &libraryIndex)
            guard !bytes.isEmpty else {
                continue
            }
            output += bytes
            count += 1
        }
        return (output, count)
    }

    /// The command as it appears in the library; empty when the library drops it.
    private func converted(_ command: RawLoadCommand, libraryIndex: inout Int) throws -> [UInt8] {
        switch command.type {
        case LoadCommandType.loadDylinker, LoadCommandType.codeSignature, LoadCommandType.idDylib:
            // Libraries have no dynamic linker command, the signer adds a fresh signature, and our own
            // LC_ID_DYLIB is already first.
            return []
        case LoadCommandType.segment64:
            return try patchedSegment(command.bytes)
        case LoadCommandType.buildVersion:
            var bytes = command.bytes
            guard bytes.count >= 24 else {
                throw MachOError.malformed("LC_BUILD_VERSION is too short")
            }
            bytes.storeLE(platform.buildVersionPlatform, at: 8)
            bytes.storeLE(MachO.minimumIOS, at: 12)
            bytes.storeLE(MachO.iOSSDK, at: 16)
            return bytes
        case let type where LoadCommandType.libraryReferences.contains(type):
            let library = libraries[libraryIndex]
            libraryIndex += 1
            return Self.dylibCommand(
                type: library.type,
                path: library.path,
                timestamp: library.original.timestamp,
                currentVersion: library.original.currentVersion,
                compatibilityVersion: library.original.compatibilityVersion
            )
        default:
            return command.bytes
        }
    }

    private func patchedSegment(_ original: [UInt8]) throws -> [UInt8] {
        var bytes = original
        switch try bytes.cString(in: 8..<24) {
        case "__PAGEZERO":
            // A 4 GB zero page can't be mapped into a process that is already running; keep one page just
            // below __TEXT (0x100000000 - 0x4000 for this game, as LiveContainer does).
            guard textVMAddress >= MachO.pageSize else {
                throw MachOError.malformed("__TEXT starts below the first page")
            }
            bytes.storeLE(textVMAddress - MachO.pageSize, at: 24)
            bytes.storeLE(MachO.pageSize, at: 32)
        case "__LINKEDIT":
            if let linkeditSize {
                bytes.storeLE(linkeditSize.vmSize, at: 32)
                bytes.storeLE(linkeditSize.fileSize, at: 48)
            }
        default:
            break
        }
        return bytes
    }

    /// A `dylib_command`: 24-byte header, NUL-terminated path, zero padding to a multiple of 8.
    static func dylibCommand(
        type: UInt32, path: String, timestamp: UInt32, currentVersion: UInt32, compatibilityVersion: UInt32
    ) -> [UInt8] {
        let name = Array(path.utf8)
        let size = (24 + name.count + 1 + 7) & ~7
        var bytes: [UInt8] = []
        bytes.reserveCapacity(size)
        bytes.appendLE(type)
        bytes.appendLE(UInt32(size))
        bytes.appendLE(24)
        bytes.appendLE(timestamp)
        bytes.appendLE(currentVersion)
        bytes.appendLE(compatibilityVersion)
        bytes += name
        bytes += [UInt8](repeating: 0, count: size - bytes.count)
        return bytes
    }
}
