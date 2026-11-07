/// Reads fixed-width integers from raw bytes without alignment requirements.
extension UnsafeRawBufferPointer {
    /// Reads a big-endian `UInt32` at `offset`, or `nil` past the end.
    func uint32BE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= count - 4 else {
            // Callers turn a short read into the error that fits their context.
            return nil
        }
        return UInt32(bigEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    /// Reads a big-endian `UInt64` at `offset`, or `nil` past the end.
    func uint64BE(at offset: Int) -> UInt64? {
        guard offset >= 0, offset <= count - 8 else {
            // Callers turn a short read into the error that fits their context.
            return nil
        }
        return UInt64(bigEndian: loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    /// Reads a little-endian `UInt32` at `offset`, or `nil` past the end.
    func uint32LE(at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= count - 4 else {
            // Callers turn a short read into the error that fits their context.
            return nil
        }
        return UInt32(littleEndian: loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }
}
