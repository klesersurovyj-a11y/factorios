public import Foundation

extension HFSPlusVolume {
    /// Bytes read from the volume and written per step; files are streamed, never held in memory whole.
    private static let pieceSize = 1 << 20

    /// An item to write, with its path relative to the extracted item.
    private struct PlannedItem {
        let relativePath: String
        let item: HFSItem
    }

    /// Writes `item` (a folder tree, file or symbolic link) to `destination`, which becomes the item itself.
    ///
    /// - Parameters:
    ///   - item: What to extract.
    ///   - destination: Where the item goes; a folder's contents go inside it.
    ///   - skipping: Called with each path relative to `item`; items for which it returns true (and everything
    ///     inside them) are not written.
    ///   - progress: Called as file contents are written.
    /// - Throws: `DiskImageError` when the volume can't be read, a file is compressed, or writing fails.
    public func extract(
        _ item: HFSItem,
        to destination: URL,
        skipping: (String) -> Bool,
        progress: (ExtractionProgress) -> Void
    ) throws {
        var plan = [PlannedItem]()
        try collect(item, relativePath: "", skipping: skipping, into: &plan)
        let total = plan.reduce(0) { $0 + ($1.item.kind == .file ? $1.item.size : 0) }
        var done: UInt64 = 0
        progress(ExtractionProgress(bytesDone: 0, bytesTotal: total))
        for planned in plan {
            let url = Self.url(of: planned, in: destination)
            try writing(url) {
                switch planned.item.kind {
                case .directory:
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                case .symlink:
                    try writeSymlink(planned.item, to: url)
                case .file:
                    try writeFile(planned.item, to: url) { written in
                        done += written
                        progress(ExtractionProgress(bytesDone: done, bytesTotal: total))
                    }
                }
            }
        }
        // Folders get their permissions last, deepest first, so read-only folders can be filled first.
        for planned in plan.reversed() where planned.item.kind == .directory {
            let url = Self.url(of: planned, in: destination)
            try writing(url) { try setPermissions(planned.item.mode, of: url) }
        }
    }

    /// Lists the tree under `item` in write order (folders before their contents); fails before anything is written
    /// if a file is compressed.
    private func collect(
        _ item: HFSItem,
        relativePath: String,
        skipping: (String) -> Bool,
        into plan: inout [PlannedItem]
    ) throws {
        guard item.kind == .directory || !item.isCompressed else { throw DiskImageError.compressedFile(item.path) }
        plan.append(PlannedItem(relativePath: relativePath, item: item))
        let contents = try item.kind == .directory ? children(of: item) : []
        for child in contents {
            let childPath = relativePath.isEmpty ? child.name : relativePath + "/" + child.name
            if !skipping(childPath) {
                try collect(child, relativePath: childPath, skipping: skipping, into: &plan)
            }
        }
    }

    private static func url(of planned: PlannedItem, in destination: URL) -> URL {
        planned.relativePath.isEmpty ? destination : destination.appendingPathComponent(planned.relativePath)
    }

    private func writeFile(_ item: HFSItem, to url: URL, written: (UInt64) -> Void) throws {
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw DiskImageError.writeFailed("\(item.path): the file couldn't be created")
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try storage.forEachPiece(of: item.fork, maximumPieceSize: Self.pieceSize) { piece in
                try handle.write(contentsOf: piece)
                written(UInt64(piece.count))
            }
        } catch {
            try? handle.close()
            throw error
        }
        try handle.close()
        try setPermissions(item.mode, of: url)
    }

    private func writeSymlink(_ item: HFSItem, to url: URL) throws {
        guard item.size > 0, item.size <= 4_096 else {
            throw DiskImageError.malformedVolume("the symbolic link \(item.path) has a bad target")
        }
        let data = try storage.read(item.fork, at: 0, count: Int(item.size))
        guard let target = String(bytes: data, encoding: .utf8) else {
            throw DiskImageError.malformedVolume("the symbolic link \(item.path) has a bad target")
        }
        try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false), withDestinationPath: target)
    }

    private func setPermissions(_ mode: UInt16, of url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: Int(mode)],
            ofItemAtPath: url.path(percentEncoded: false)
        )
    }

    /// Runs a file system step, reporting its failure as `DiskImageError.writeFailed` for `url`.
    private func writing(_ url: URL, _ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as DiskImageError {
            throw error
        } catch {
            throw DiskImageError.writeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
