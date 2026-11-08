import Foundation

/// Finds the arm64 Mach-O inside a universal (fat) binary, or accepts a thin one.
enum FatBinary {
    /// `sizeof(fat_arch)`; Factorio ships a classic universal binary, not one with 64-bit `fat_arch_64` entries.
    private static let entrySize = 20

    /// Byte range of the arm64 slice, relative to the start of `data`.
    static func arm64Slice(of data: Data) throws -> Range<Int> {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) throws -> Range<Int> in
            guard let magic = bytes.uint32BE(at: 0) else {
                throw MachOError.notMachO
            }
            guard magic == MachO.fatMagic else {
                guard magic.byteSwapped == MachO.magic64 else {
                    throw MachOError.notMachO
                }
                return 0..<bytes.count
            }
            return try fatSlice(in: bytes)
        }
    }

    /// Walks the big-endian `fat_arch` entries.
    private static func fatSlice(in bytes: UnsafeRawBufferPointer) throws -> Range<Int> {
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
            guard let offset = bytes.uint32BE(at: entry + 8).map(Int.init),
                let size = bytes.uint32BE(at: entry + 12).map(Int.init),
                offset <= bytes.count, size <= bytes.count - offset
            else {
                throw MachOError.malformed("the arm64 slice lies outside the file")
            }
            return offset..<offset + size
        }
        throw MachOError.noArm64Slice
    }
}

extension UnsafeRawBufferPointer {
    /// Reads a big-endian `UInt32` at `offset`, or `nil` past the end; callers pick the error that fits.
    func uint32BE(at offset: Int) -> UInt32? {
        offset >= 0 && offset <= count - 4
            ? UInt32(bigEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self)) : nil
    }
}
