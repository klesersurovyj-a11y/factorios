import Foundation

/// Bounds-checked little-endian access to the Mach-O header and load commands.
extension Array where Element == UInt8 {
    /// Reads a little-endian `UInt32` at `offset`.
    func uint32LE(at offset: Int) throws -> UInt32 {
        UInt32(littleEndian: try load(at: offset))
    }

    /// Reads a little-endian `UInt64` at `offset`.
    func uint64LE(at offset: Int) throws -> UInt64 {
        UInt64(littleEndian: try load(at: offset))
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

    /// Overwrites the bytes at `offset` with `value`, little-endian.
    mutating func storeLE(_ value: some FixedWidthInteger, at offset: Int) {
        withUnsafeMutableBytes { $0.storeBytes(of: value.littleEndian, toByteOffset: offset, as: type(of: value)) }
    }

    /// Appends `value`, little-endian.
    mutating func appendLE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    private func load<T: FixedWidthInteger>(at offset: Int) throws -> T {
        guard offset >= 0, offset <= count - MemoryLayout<T>.size else {
            throw MachOError.malformed("load commands end before offset \(offset)")
        }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: T.self) }
    }
}
