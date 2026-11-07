import Foundation

/// A read-only HFS+ or HFSX volume: the catalog and extents overflow B-trees, hard links and symbolic links.
public final class HFSPlusVolume: Sendable {
    private enum Header {
        static let offset: UInt64 = 1_024
        static let hfsPlusSignature: UInt16 = 0x482B  // 'H+'
        static let hfsxSignature: UInt16 = 0x4858  // 'HX'
        static let extentsFork = 0xC0
        static let catalogFork = 0x110
        static let catalogFileID: UInt32 = 4
        static let rootParentID: UInt32 = 1
        static let rootFolderID: UInt32 = 2
    }

    /// The volume's root folder; its name is the volume name.
    public let root: HFSItem
    let storage: HFSStorage
    private let catalog: HFSBTree
    private let extentsOverflow: HFSBTree
    /// The private folders holding the targets of file and folder hard links, if the volume has them.
    private let fileLinkDirectory: UInt32?
    private let directoryLinkDirectory: UInt32?

    /// Reads the volume header at offset 1024 of `source` and opens the volume's B-trees.
    public init(source: any RandomAccessSource) throws {
        let header = try source.read(at: Header.offset, count: 512)
        let signature = try header.diskUInt16(at: 0)
        guard signature == Header.hfsPlusSignature || signature == Header.hfsxSignature else {
            throw DiskImageError.notHFSPlus
        }
        let blockSize = try header.diskUInt32(at: 40)
        guard blockSize >= 512, blockSize.nonzeroBitCount == 1 else {
            throw DiskImageError.malformedVolume("bad allocation block size")
        }
        let isHFSX = signature == Header.hfsxSignature
        let blocks = HFSStorage(source: source, blockSize: UInt64(blockSize))
        let overflow = try HFSBTree(
            storage: blocks,
            fork: HFSFork(data: header, at: Header.extentsFork),
            isHFSX: isHFSX
        )
        var catalogFork = try HFSFork(data: header, at: Header.catalogFork)
        if catalogFork.coveredBlocks < UInt64(catalogFork.totalBlocks) {
            catalogFork.extents += try overflow.overflowExtents(fileID: Header.catalogFileID)
        }
        let catalogTree = try HFSBTree(storage: blocks, fork: catalogFork, isHFSX: isHFSX)
        storage = blocks
        extentsOverflow = overflow
        catalog = catalogTree
        root = try Self.rootItem(in: catalogTree)
        let rootRecords = try catalogTree.catalogRecords(parent: Header.rootFolderID)
        fileLinkDirectory = try Self.folderID(named: HFSName.fileLinkDirectory, in: rootRecords)
        directoryLinkDirectory = try Self.folderID(named: HFSName.directoryLinkDirectory, in: rootRecords)
    }

    /// The item at a `/`-separated path from the volume root; an empty path is the root.
    public func lookup(_ path: String) throws -> HFSItem {
        var item = root
        for component in path.split(separator: "/") where component != "." {
            let name = String(component).precomposedStringWithCanonicalMapping
            guard item.kind == .directory else { throw DiskImageError.notADirectory(item.path) }
            guard let child = try children(of: item).first(where: { $0.name == name }) else {
                throw DiskImageError.notFound(path)
            }
            item = child
        }
        return item
    }

    /// The items in a folder, in catalog order, with hard links resolved; the volume's private metadata folders
    /// are left out.
    public func children(of directory: HFSItem) throws -> [HFSItem] {
        guard directory.kind == .directory else { throw DiskImageError.notADirectory(directory.path) }
        var items = [HFSItem]()
        for record in try catalog.catalogRecords(parent: directory.id) {
            let units = try HFSBTree.name(of: record.key)
            if directory.id == Header.rootFolderID, HFSName.hiddenAtRoot.contains(units) {
                continue
            }
            let name = HFSName.string(units)
            let path = directory.path.isEmpty ? name : directory.path + "/" + name
            items.append(try item(named: name, path: path, entry: CatalogEntry(record.value)))
        }
        return items
    }

    private func item(named name: String, path: String, entry linkOrItem: CatalogEntry) throws -> HFSItem {
        let entry = try resolve(linkOrItem, path: path)
        let kind: HFSItem.Kind = entry.isFolder ? .directory : entry.isSymlink ? .symlink : .file
        let fork = try completed(entry.dataFork, fileID: entry.id)
        return HFSItem(
            name: name,
            path: path,
            kind: kind,
            size: fork.logicalSize,
            mode: entry.permissions,
            id: entry.id,
            fork: fork,
            isCompressed: entry.isCompressed
        )
    }

    /// The record a hard link stands for (`iNode<n>` or `dir_<n>` in the private folders), or `entry` itself.
    private func resolve(_ entry: CatalogEntry, path: String) throws -> CatalogEntry {
        let folder: UInt32?
        let name: String
        switch entry.link {
        case nil:
            return entry
        case .file(let number):
            folder = fileLinkDirectory
            name = "iNode\(number)"
        case .directory(let number):
            folder = directoryLinkDirectory
            name = "dir_\(number)"
        }
        guard let folder, let record = try catalog.catalogRecord(parent: folder, name: Array(name.utf16)) else {
            throw DiskImageError.malformedVolume("the hard link \(path) has no target")
        }
        return try CatalogEntry(record.value)
    }

    /// The fork with the extents beyond the first eight, from the extents overflow tree.
    private func completed(_ fork: HFSFork, fileID: UInt32) throws -> HFSFork {
        guard fork.coveredBlocks < UInt64(fork.totalBlocks) else { return fork }
        var complete = fork
        complete.extents += try extentsOverflow.overflowExtents(fileID: fileID)
        guard complete.coveredBlocks >= UInt64(fork.totalBlocks) else {
            throw DiskImageError.malformedVolume("file \(fileID) is missing extents")
        }
        return complete
    }

    private static func rootItem(in catalog: HFSBTree) throws -> HFSItem {
        for record in try catalog.catalogRecords(parent: Header.rootParentID) {
            let entry = try CatalogEntry(record.value)
            if entry.isFolder, entry.id == Header.rootFolderID {
                return HFSItem(
                    name: HFSName.string(try HFSBTree.name(of: record.key)),
                    path: "",
                    kind: .directory,
                    size: 0,
                    mode: entry.permissions,
                    id: entry.id,
                    fork: .empty,
                    isCompressed: false
                )
            }
        }
        throw DiskImageError.malformedVolume("the catalog has no root folder")
    }

    private static func folderID(named name: [UInt16], in records: [HFSRecord]) throws -> UInt32? {
        for record in records {
            guard try HFSBTree.name(of: record.key) == name else { continue }
            let entry = try CatalogEntry(record.value)
            return entry.isFolder ? entry.id : nil
        }
        return nil
    }
}
