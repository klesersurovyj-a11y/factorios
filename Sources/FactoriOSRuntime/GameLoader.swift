import Darwin
import FactoriOSCompat
import FactoriOSCore
import Foundation
import MachO

/// Loads the converted game library, points its recorded slots at the compatibility layer and calls its entry point.
struct GameLoader {
    /// `int main(int argc, char **argv, char **envp, char **apple)`, as dyld calls an executable's LC_MAIN entry.
    private typealias Entry =
        @convention(c) (
            Int32,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32

    private let entry: UnsafeRawPointer

    /// Reads the slot manifest the converter wrote next to the library.
    static func readManifest(_ url: URL) throws -> SymbolSlotManifest {
        guard let data = try? Data(contentsOf: url) else {
            throw GameLaunchError.notInstalled
        }
        return try JSONDecoder().decode(SymbolSlotManifest.self, from: data)
    }

    /// dlopens the library (running its initializers), patches every recorded slot and finds the entry point.
    static func load(library: URL, manifest: SymbolSlotManifest) throws -> Self {
        // Load order: dlopen runs the game's initializers before any slot points at the compatibility layer. That is
        // safe because scripts/inspect-binary's load-time report shows the 2.1.23 demo's 448 __mod_init_func
        // initializers reach no Mac-only or replaced import and the image has no +load methods (`mise run inspect`
        // reports both). Slots are then filled with vm_protect, since __DATA_CONST is
        // read-only after binding, and only then is the entry called.
        // The handle is never closed: the game stays loaded until the process exits.
        guard dlopen(library.path, RTLD_NOW | RTLD_LOCAL) != nil else {
            throw GameLaunchError.loadFailed(dlerror().map { String(cString: $0) } ?? "unknown dyld error")
        }
        let header = try imageHeader(path: library.path)
        let layout = try ImageLayout(header: header)
        try patchSlots(header: header, size: layout.size, manifest: manifest)
        return Self(entry: header + Int(layout.entryOffset))
    }

    /// Calls the game's entry point on the current (main) thread with `arguments` as argv; returns its status.
    func callEntry(arguments: [String], executablePath: String) -> Int32 {
        let environment = ProcessInfo.processInfo.environment.map { "\($0.key)=\($0.value)" }
        // The arrays stay allocated for the rest of the process, as the kernel's argv and envp do.
        let argv = Self.cStrings(arguments)
        let envp = Self.cStrings(environment)
        let apple = Self.cStrings(["executable_path=\(executablePath)"])
        let main = unsafeBitCast(entry, to: Entry.self)
        return main(Int32(arguments.count), argv, envp, apple)
    }

    private static func cStrings(_ strings: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
        let array = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for (index, string) in strings.enumerated() {
            array[index] = strdup(string)
        }
        array[strings.count] = nil
        return array
    }

    /// The mach header of the loaded image at `path`, found among dyld's images.
    private static func imageHeader(path: String) throws -> UnsafeRawPointer {
        let target = canonicalPath(path)
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index), canonicalPath(String(cString: name)) == target,
                let header = _dyld_get_image_header(index)
            else {
                continue
            }
            return UnsafeRawPointer(header)
        }
        throw GameLaunchError.imageNotFound
    }

    /// `path` with symbolic links resolved (dyld may report /private/var for /var).
    private static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return path
        }
        defer {
            free(resolved)
        }
        return String(cString: resolved)
    }

    private static func patchSlots(header: UnsafeRawPointer, size: UInt64, manifest: SymbolSlotManifest) throws {
        let replacements = CompatTable.replacements()
        let pointerSize = UInt64(MemoryLayout<UnsafeRawPointer>.size)
        for (symbol, offsets) in manifest.slots {
            guard let replacement = replacements[symbol] else {
                throw GameLaunchError.noReplacement(symbol: symbol)
            }
            for offset in offsets {
                guard offset.isMultiple(of: pointerSize), size >= pointerSize, offset <= size - pointerSize else {
                    throw GameLaunchError.slotOutsideImage(symbol: symbol)
                }
                let slot = UnsafeMutableRawPointer(mutating: header + Int(offset))
                let result = FOSCompatWriteSlot(slot, replacement)
                guard result == KERN_SUCCESS else {
                    throw GameLaunchError.slotNotWritable(symbol: symbol, code: result)
                }
            }
        }
    }
}

/// What the loader needs from a loaded image's load commands.
private struct ImageLayout {
    private static let headerSize = 32
    private static let commandCountOffset = 16
    private static let segmentCommand: UInt32 = 0x19  // LC_SEGMENT_64
    private static let mainCommand: UInt32 = 0x8000_0028  // LC_MAIN

    /// LC_MAIN's entryoff: the entry point's offset from the mach header.
    let entryOffset: UInt64
    /// The span of the image's segments from the mach header (`__TEXT`) to the end of the last one.
    let size: UInt64

    init(header: UnsafeRawPointer) throws {
        let count = header.loadUnaligned(fromByteOffset: Self.commandCountOffset, as: UInt32.self)
        var offset = Self.headerSize
        var entry: UInt64?
        var textAddress: UInt64?
        var end: UInt64 = 0
        for _ in 0..<count {
            let command = header.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            let commandSize = Int(header.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            if command == Self.mainCommand {
                entry = header.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self)
            } else if command == Self.segmentCommand {
                let segment = Segment(header: header, at: offset)
                if segment.name == "__TEXT" {
                    textAddress = segment.address
                }
                if segment.name != "__PAGEZERO" {
                    end = max(end, segment.address + segment.size)
                }
            }
            guard commandSize > 0 else {
                break
            }
            offset += commandSize
        }
        guard let entry, let textAddress, end > textAddress, entry < end - textAddress else {
            throw GameLaunchError.noEntryPoint
        }
        entryOffset = entry
        size = end - textAddress
    }
}

/// A segment_command_64's name, vmaddr and vmsize.
private struct Segment {
    let name: String
    let address: UInt64
    let size: UInt64

    init(header: UnsafeRawPointer, at offset: Int) {
        let nameBytes = (0..<16).map { header.loadUnaligned(fromByteOffset: offset + 8 + $0, as: UInt8.self) }
        name = String(bytes: nameBytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        address = header.loadUnaligned(fromByteOffset: offset + 24, as: UInt64.self)
        size = header.loadUnaligned(fromByteOffset: offset + 32, as: UInt64.self)
    }
}
