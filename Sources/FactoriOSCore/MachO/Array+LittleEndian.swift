import Foundation

/// Bounds-checked little-endian access to the Mach-O header and load commands.
extension Array where Element == UInt8 {
    /// Reads a little-endian `UInt32` at `offset`.
    func uint32LE(at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= count - 4 else {
            throw MachOError.malformed("load commands end before offset \(offset)")
        }
        var value: UInt32 = 0
        for index in 0..<4 {
            value |= UInt32(self[offset + index]) << (8 * index)
        }
        return value
    }

    /// Reads a little-endian `UInt64` at `offset`.
    func uint64LE(at offset: Int) throws -> UInt64 {
        let low = try uint32LE(at: offset)
        let high = try uint32LE(at: offset + 4)
        return UInt64(high) << 32 | UInt64(low)
    }

    /// Reads a NUL-terminated (or range-terminated) UTF-8 string from `range`.
    func cString(in range: Range<Int>) throws -> String {
        guard range.lowerBound >= 0, range.upperBound <= count else {
            throw MachOError.malformed("string at \(range.lowerBound) runs past the load commands")
        }
        let end = self[range].firstIndex(of: 0) ?? range.upperBound
        guard let string = String(bytes: self[range.lowerBound..<end], encoding: .utf8) else {
            throw MachOError.malformed("string at \(range.lowerBound) isn't UTF-8")
        }
        return string
    }

    /// Overwrites four bytes at `offset` with `value`, little-endian.
    mutating func storeLE(_ value: UInt32, at offset: Int) {
        for index in 0..<4 {
            self[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index))
        }
    }

    /// Overwrites eight bytes at `offset` with `value`, little-endian.
    mutating func storeLE(_ value: UInt64, at offset: Int) {
        storeLE(UInt32(truncatingIfNeeded: value), at: offset)
        storeLE(UInt32(truncatingIfNeeded: value >> 32), at: offset + 4)
    }

    /// Appends `value`, little-endian.
    mutating func appendLE(_ value: UInt32) {
        for index in 0..<4 {
            append(UInt8(truncatingIfNeeded: value >> (8 * index)))
        }
    }
}
