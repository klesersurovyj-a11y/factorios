import Foundation

/// An HFS+ B-tree (catalog or extents overflow) stored in a fork.
struct HFSBTree: Sendable {
    private static let leafKind: Int8 = -1
    private static let indexKind: Int8 = 0
    private static let maximumDepth = 16

    private let storage: HFSStorage
    private let fork: HFSFork
    private let nodeSize: Int
    private let rootNode: UInt32
    private let totalNodes: UInt32
    /// Whether names compare as binary UTF-16 (HFSX with `kHFSBinaryCompare`) rather than case-insensitively.
    let binaryNames: Bool

    /// Reads the header record of the tree in `fork`.
    init(storage: HFSStorage, fork: HFSFork, isHFSX: Bool) throws {
        self.storage = storage
        self.fork = fork
        let header = try storage.read(fork, at: 0, count: 512)
        nodeSize = Int(try header.diskUInt16(at: 32))
        rootNode = try header.diskUInt32(at: 16)
        totalNodes = try header.diskUInt32(at: 36)
        binaryNames = try isHFSX && header.diskUInt8(at: 51) == 0xBC
        guard nodeSize >= 512, nodeSize.nonzeroBitCount == 1,
            UInt64(totalNodes) * UInt64(nodeSize) <= fork.coveredBlocks * storage.blockSize
        else {
            throw DiskImageError.malformedVolume("bad B-tree header")
        }
    }

    /// Calls `visit` with each leaf record from the one where a key `isAtMost` the target would be inserted, in key
    /// order, until `visit` returns false.
    ///
    /// `isAtMost` tells whether a key sorts before or equal to the target; index nodes are descended through the
    /// last record whose key does.
    func forEachRecord(from isAtMost: (Data) throws -> Bool, _ visit: (HFSRecord) throws -> Bool) throws {
        var current = try leaf(for: isAtMost)
        var visited: UInt32 = 0
        walk: while let node = current {
            for index in 0..<node.recordCount {
                guard try visit(node.record(index)) else { break walk }
            }
            visited += 1
            guard visited <= totalNodes else { throw DiskImageError.malformedVolume("B-tree leaves loop") }
            current = try node.forwardLink == 0 ? nil : self.node(node.forwardLink)
            guard current?.kind ?? Self.leafKind == Self.leafKind else {
                throw DiskImageError.malformedVolume("B-tree leaf links to a non-leaf node")
            }
        }
    }

    private func leaf(for isAtMost: (Data) throws -> Bool) throws -> HFSNode? {
        guard rootNode != 0 else {
            // An empty tree has no leaves.
            return nil
        }
        var number = rootNode
        for _ in 0..<Self.maximumDepth {
            let node = try node(number)
            if node.kind == Self.leafKind {
                return node
            }
            guard node.kind == Self.indexKind, node.recordCount > 0 else {
                throw DiskImageError.malformedVolume("bad B-tree index node")
            }
            number = try node.record(0).value.diskUInt32(at: 0)
            for index in 1..<node.recordCount {
                let record = try node.record(index)
                guard try isAtMost(record.key) else { break }
                number = try record.value.diskUInt32(at: 0)
            }
        }
        throw DiskImageError.malformedVolume("B-tree is too deep")
    }

    private func node(_ number: UInt32) throws -> HFSNode {
        guard number < totalNodes else { throw DiskImageError.malformedVolume("B-tree node out of range") }
        return try HFSNode(data: storage.read(fork, at: UInt64(number) * UInt64(nodeSize), count: nodeSize))
    }
}

/// A B-tree node: a 14-byte descriptor, records, and the record offsets stored backwards at the end.
private struct HFSNode {
    let data: Data
    let forwardLink: UInt32
    let kind: Int8
    let recordCount: Int

    init(data: Data) throws {
        self.data = data
        forwardLink = try data.diskUInt32(at: 0)
        kind = Int8(bitPattern: try data.diskUInt8(at: 8))
        recordCount = Int(try data.diskUInt16(at: 10))
        guard 14 + 2 * (recordCount + 1) <= data.count else {
            throw DiskImageError.malformedVolume("B-tree node holds too many records")
        }
    }

    func record(_ index: Int) throws -> HFSRecord {
        let start = Int(try data.diskUInt16(at: data.count - 2 * (index + 1)))
        let end = Int(try data.diskUInt16(at: data.count - 2 * (index + 2)))
        guard start >= 14, start + 2 <= end, end <= data.count - 2 * (recordCount + 1) else {
            throw DiskImageError.malformedVolume("bad B-tree record offsets")
        }
        let keyLength = Int(try data.diskUInt16(at: start))
        guard start + 2 + keyLength <= end else { throw DiskImageError.malformedVolume("B-tree key too long") }
        return HFSRecord(
            key: try data.diskBytes(at: start + 2, count: keyLength),
            value: try data.diskBytes(at: start + 2 + keyLength, count: end - start - 2 - keyLength)
        )
    }
}

/// A B-tree record: the key without its length field, and what follows it (a child node number in index nodes).
struct HFSRecord {
    let key: Data
    let value: Data
}

extension HFSBTree {
    /// The folder and file records whose parent is `parent`, in catalog order (thread records left out).
    func catalogRecords(parent: UInt32) throws -> [HFSRecord] {
        var records = [HFSRecord]()
        let isAtMost = { (key: Data) throws -> Bool in
            let keyParent = try key.diskUInt32(at: 0)
            guard keyParent == parent else { return keyParent < parent }
            return try key.diskUInt16(at: 4) == 0
        }
        try forEachRecord(from: isAtMost) { record in
            let keyParent = try record.key.diskUInt32(at: 0)
            if keyParent == parent, (1...2).contains(try record.value.diskUInt16(at: 0)) {
                records.append(record)
            }
            return keyParent <= parent
        }
        return records
    }

    /// The folder or file record named `name` in the folder `parent`, if there is one.
    func catalogRecord(parent: UInt32, name: [UInt16]) throws -> HFSRecord? {
        let isAtMost = { (key: Data) throws -> Bool in
            let keyParent = try key.diskUInt32(at: 0)
            guard keyParent == parent else { return keyParent < parent }
            return HFSName.isOrdered(try Self.name(of: key), atMost: name, binary: binaryNames)
        }
        var found: HFSRecord?
        try forEachRecord(from: isAtMost) { record in
            let keyParent = try record.key.diskUInt32(at: 0)
            guard keyParent <= parent else { return false }
            guard keyParent == parent else { return true }
            let keyName = try Self.name(of: record.key)
            if keyName == name, (1...2).contains(try record.value.diskUInt16(at: 0)) {
                found = record
                return false
            }
            return HFSName.isOrdered(keyName, atMost: name, binary: binaryNames)
        }
        return found
    }

    /// The name in a catalog key (`parentID`, then an `HFSUniStr255`).
    static func name(of key: Data) throws -> [UInt16] {
        try key.diskUTF16(at: 6, units: Int(key.diskUInt16(at: 4)))
    }

    /// The data-fork extents of `fileID` recorded in this extents overflow tree, in file order.
    func overflowExtents(fileID: UInt32) throws -> [HFSExtent] {
        let dataFork: UInt8 = 0
        let isAtMost = { (key: Data) throws -> Bool in
            let keyFile = try key.diskUInt32(at: 2)
            let keyFork = try key.diskUInt8(at: 0)
            guard (keyFile, keyFork) == (fileID, dataFork) else { return (keyFile, keyFork) < (fileID, dataFork) }
            return try key.diskUInt32(at: 6) == 0
        }
        var extents = [HFSExtent]()
        try forEachRecord(from: isAtMost) { record in
            let keyFile = try record.key.diskUInt32(at: 2)
            let keyFork = try record.key.diskUInt8(at: 0)
            if (keyFile, keyFork) == (fileID, dataFork) {
                extents.append(contentsOf: try HFSExtent.list(in: record.value, at: 0))
            }
            return (keyFile, keyFork) <= (fileID, dataFork)
        }
        return extents
    }
}
