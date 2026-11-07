public import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#elseif canImport(Musl)
    import Musl
#endif

/// Bytes that can be read at any offset: a file, or a decoded partition of a disk image.
public protocol RandomAccessSource: Sendable {
    /// The number of readable bytes.
    var size: UInt64 { get }
    /// Reads exactly `count` bytes starting at `offset`; reading past `size` throws.
    func read(at offset: UInt64, count: Int) throws -> Data
}

/// A file on disk, read with positioned reads so that any thread can read at any offset.
public final class FileSource: RandomAccessSource {
    /// The file's size in bytes.
    public let size: UInt64
    private let descriptor: Int32
    private let path: String

    /// Opens the file read-only.
    public init(url: URL) throws {
        path = url.lastPathComponent
        let file = url.withUnsafeFileSystemRepresentation { name in
            name.map { open($0, O_RDONLY) } ?? -1
        }
        guard file >= 0 else {
            throw DiskImageError.unreadable("\(url.lastPathComponent): \(Self.lastErrorMessage())")
        }
        var status = stat()
        guard fstat(file, &status) == 0 else {
            let reason = Self.lastErrorMessage()
            close(file)
            throw DiskImageError.unreadable("\(url.lastPathComponent): \(reason)")
        }
        descriptor = file
        size = UInt64(status.st_size)
    }

    deinit {
        close(descriptor)
    }

    /// Reads exactly `count` bytes at `offset`.
    public func read(at offset: UInt64, count: Int) throws -> Data {
        guard count >= 0, offset <= size, UInt64(count) <= size - offset else { throw DiskImageError.truncated }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else {
                // A zero-byte read has no buffer and nothing to fill.
                return
            }
            var done = 0
            while done < count {
                let result = pread(descriptor, base + done, count - done, off_t(offset) + off_t(done))
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    let reason = result < 0 ? Self.lastErrorMessage() : "unexpected end of file"
                    throw DiskImageError.unreadable("\(path): \(reason)")
                }
                done += result
            }
        }
        return data
    }

    private static func lastErrorMessage() -> String {
        String(cString: strerror(errno))
    }
}
