import Foundation

/// Bounds-checked big-endian reads; offsets are relative to the start of the data, slices included.
extension Data {
    func diskUInt8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < count else { throw DiskImageError.truncated }
        return self[startIndex + offset]
    }

    func diskUInt16(at offset: Int) throws -> UInt16 {
        UInt16(try bigEndianValue(at: offset, size: 2))
    }

    func diskUInt32(at offset: Int) throws -> UInt32 {
        UInt32(try bigEndianValue(at: offset, size: 4))
    }

    func diskUInt64(at offset: Int) throws -> UInt64 {
        try bigEndianValue(at: offset, size: 8)
    }

    /// A copy of `length` bytes at `offset`, indexed from zero.
    func diskBytes(at offset: Int, count length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset <= count - length else { throw DiskImageError.truncated }
        return Data(self[(startIndex + offset)..<(startIndex + offset + length)])
    }

    /// Big-endian UTF-16 code units.
    func diskUTF16(at offset: Int, units: Int) throws -> [UInt16] {
        guard offset >= 0, units >= 0, offset <= count - 2 * units else { throw DiskImageError.truncated }
        var result = [UInt16]()
        result.reserveCapacity(units)
        var index = startIndex + offset
        for _ in 0..<units {
            result.append(UInt16(self[index]) << 8 | UInt16(self[index + 1]))
            index += 2
        }
        return result
    }

    private func bigEndianValue(at offset: Int, size: Int) throws -> UInt64 {
        guard offset >= 0, offset <= count - size else { throw DiskImageError.truncated }
        var value: UInt64 = 0
        for index in (startIndex + offset)..<(startIndex + offset + size) {
            value = value << 8 | UInt64(self[index])
        }
        return value
    }
}
