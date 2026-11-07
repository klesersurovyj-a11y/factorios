import Foundation

/// Finds the arm64 Mach-O inside a universal (fat) binary, or accepts a thin one.
enum FatBinary {
    /// Byte range of the arm64 slice, relative to the start of `data`.
    static func arm64Slice(of data: Data) throws -> Range<Int> {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws -> Range<Int> in
            guard let magic = bytes.uint32BE(at: 0) else {
                throw MachOError.notMachO
            }
            switch magic {
            case MachO.fatMagic:
                return try fatSlice(in: bytes, entrySize: 20, wide: false)
            case MachO.fatMagic64:
                return try fatSlice(in: bytes, entrySize: 32, wide: true)
            default:
                guard bytes.uint32LE(at: 0) == MachO.magic64 else {
                    throw MachOError.notMachO
                }
                return 0..<bytes.count
            }
        }
    }

    /// Walks `fat_arch` (20 bytes) or `fat_arch_64` (32 bytes) entries, all big-endian.
    private static func fatSlice(in bytes: UnsafeRawBufferPointer, entrySize: Int, wide: Bool) throws -> Range<Int> {
        guard let count = bytes.uint32BE(at: 4) else {
            throw MachOError.notMachO
        }
        for index in 0..<Int(count) {
            let entry = 8 + index * entrySize
            guard let cpuType = bytes.uint32BE(at: entry) else {
                throw MachOError.malformed("universal header ends inside its architecture list")
            }
            guard cpuType == MachO.cpuTypeARM64 else {
                continue
            }
            let offset: UInt64?
            let size: UInt64?
            if wide {
                offset = bytes.uint64BE(at: entry + 8)
                size = bytes.uint64BE(at: entry + 16)
            } else {
                offset = bytes.uint32BE(at: entry + 8).map(UInt64.init)
                size = bytes.uint32BE(at: entry + 12).map(UInt64.init)
            }
            guard let offset, let size, offset <= UInt64(bytes.count), size <= UInt64(bytes.count) - offset else {
                throw MachOError.malformed("the arm64 slice lies outside the file")
            }
            return Int(offset)..<Int(offset + size)
        }
        throw MachOError.noArm64Slice
    }
}
