import Foundation

/// Reads ULEB128/SLEB128 numbers and strings from an opcode stream inside the image.
struct OpcodeCursor {
    let image: UnsafeMutableRawBufferPointer
    private(set) var position: Int
    let end: Int

    init(image: UnsafeMutableRawBufferPointer, range: Range<Int>) {
        self.image = image
        position = range.lowerBound
        end = range.upperBound
    }

    var isAtEnd: Bool {
        position >= end
    }

    mutating func readByte() throws -> UInt8 {
        guard position < end else {
            throw MachOError.malformed("a bind stream ends inside an opcode")
        }
        defer { position += 1 }
        return image[position]
    }

    mutating func uleb() throws -> UInt64 {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            let byte = try readByte()
            guard shift < 64 else {
                throw MachOError.malformed("a ULEB128 number in a bind stream is too long")
            }
            value |= UInt64(byte & 0x7F) << shift
            shift += 7
            if byte & 0x80 == 0 {
                return value
            }
        }
    }

    mutating func sleb() throws -> Int64 {
        var value: Int64 = 0
        var shift: Int64 = 0
        var byte: UInt8
        repeat {
            byte = try readByte()
            guard shift < 64 else {
                throw MachOError.malformed("a SLEB128 number in a bind stream is too long")
            }
            value |= Int64(byte & 0x7F) << shift
            shift += 7
        } while byte & 0x80 != 0
        if shift < 64, byte & 0x40 != 0 {
            value |= -1 << shift
        }
        return value
    }

    mutating func cString() throws -> String {
        let start = position
        while try readByte() != 0 {
            continue
        }
        guard
            let string = String(
                bytes: UnsafeRawBufferPointer(rebasing: image[start..<position - 1]),
                encoding: .utf8
            )
        else {
            throw MachOError.malformed("a symbol name at \(start) isn't UTF-8")
        }
        return string
    }
}

/// The registers a bind opcode stream sets before each bind (dyld's `ImageLoaderMachOCompressed` model).
struct BindState {
    /// `BIND_TYPE_POINTER`; other types patch instruction fields, not 8-byte slots.
    static let pointerType: UInt8 = 1

    var ordinal = 0
    var symbol = ""
    /// File offset of the `BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM` byte that named `symbol`.
    var symbolOpcode: Int?
    var isRedirected = false
    var type = pointerType
    var segmentIndex: Int?
    var offset: UInt64 = 0

    /// Applies an opcode that only sets a register; returns `false` for opcodes that bind.
    mutating func apply(
        _ opcode: UInt8,
        immediate: UInt8,
        at opcodePosition: Int,
        cursor: inout OpcodeCursor,
        redirected: Set<String>
    ) throws -> Bool {
        switch opcode {
        case BindOpcode.setDylibOrdinalImm:
            ordinal = Int(immediate)
        case BindOpcode.setDylibOrdinalULEB:
            ordinal = Int(clamping: try cursor.uleb())
        case BindOpcode.setDylibSpecialImm:
            // Special ordinals are small negative numbers stored in the immediate's four bits.
            ordinal = immediate == 0 ? 0 : Int(Int8(bitPattern: BindOpcode.mask | immediate))
        case BindOpcode.setSymbolTrailingFlagsImm:
            symbolOpcode = opcodePosition
            symbol = try cursor.cString()
            isRedirected = redirected.contains(symbol)
        case BindOpcode.setTypeImm:
            type = immediate
        case BindOpcode.setAddendSLEB:
            // The addend only changes the value dyld writes; the slot address, all the manifest needs, stays.
            _ = try cursor.sleb()
        case BindOpcode.setSegmentAndOffsetULEB:
            segmentIndex = Int(immediate)
            offset = try cursor.uleb()
        case BindOpcode.addAddrULEB:
            offset &+= try cursor.uleb()
        default:
            return false
        }
        return true
    }
}

/// Walks `LC_DYLD_INFO` bind and lazy-bind opcode streams in place: marks every symbol bound from a weak
/// library as a weak import (a length-preserving change to the opcode's immediate) and records the pointer slots
/// of redirected symbols.
struct BindStreamWalker {
    /// Which stream is walked: `BIND_OPCODE_DONE` ends a bind stream but only separates lazy-bind entries.
    enum Stream {
        case bind
        case lazyBind
    }

    private let segments: [Segment]
    private let libraries: [ConvertedLibrary]
    private let redirectedSymbols: Set<String>
    private let imageBase: UInt64
    /// Symbol → slot offsets from the image's header, in stream order (possibly repeated).
    private(set) var slots: [String: [UInt64]] = [:]

    init(segments: [Segment], libraries: [ConvertedLibrary], redirectedSymbols: Set<String>, imageBase: UInt64) {
        self.segments = segments
        self.libraries = libraries
        self.redirectedSymbols = redirectedSymbols
        self.imageBase = imageBase
    }

    mutating func walk(_ image: UnsafeMutableRawBufferPointer, range: Range<UInt64>, stream: Stream) throws {
        guard range.upperBound <= UInt64(image.count) else {
            throw MachOError.malformed("a bind stream lies outside the file")
        }
        var cursor = OpcodeCursor(image: image, range: Int(range.lowerBound)..<Int(range.upperBound))
        var state = BindState()
        while !cursor.isAtEnd {
            let opcodePosition = cursor.position
            let byte = try cursor.readByte()
            let opcode = byte & BindOpcode.mask
            let immediate = byte & BindOpcode.immediateMask
            if opcode == BindOpcode.done {
                // DONE ends a bind stream; in a lazy-bind stream it only separates entries.
                guard stream == .lazyBind else {
                    break
                }
                continue
            }
            let applied = try state.apply(
                opcode, immediate: immediate, at: opcodePosition, cursor: &cursor, redirected: redirectedSymbols
            )
            if !applied {
                try performBinds(opcode, immediate: immediate, cursor: &cursor, state: &state)
            }
        }
    }

    private mutating func performBinds(
        _ opcode: UInt8, immediate: UInt8, cursor: inout OpcodeCursor, state: inout BindState
    ) throws {
        switch opcode {
        case BindOpcode.doBind:
            try bind(state, image: cursor.image)
            state.offset &+= MachO.pointerSize
        case BindOpcode.doBindAddAddrULEB:
            try bind(state, image: cursor.image)
            state.offset &+= try cursor.uleb() &+ MachO.pointerSize
        case BindOpcode.doBindAddAddrImmScaled:
            try bind(state, image: cursor.image)
            state.offset &+= UInt64(immediate) * MachO.pointerSize + MachO.pointerSize
        case BindOpcode.doBindULEBTimesSkippingULEB:
            let count = try cursor.uleb()
            let skip = try cursor.uleb()
            guard count <= (try segment(for: state)).vmSize / MachO.pointerSize else {
                throw MachOError.malformed("a bind repeats more often than its segment has slots")
            }
            for _ in 0..<count {
                try bind(state, image: cursor.image)
                state.offset &+= skip &+ MachO.pointerSize
            }
        case BindOpcode.threaded:
            throw MachOError.threadedBindsUnsupported
        default:
            throw MachOError.malformed("unknown bind opcode 0x\(String(opcode, radix: 16))")
        }
    }

    private func segment(for state: BindState) throws -> Segment {
        guard let index = state.segmentIndex, index < segments.count else {
            throw MachOError.malformed("a bind names a segment the image doesn't have")
        }
        return segments[index]
    }

    private mutating func bind(_ state: BindState, image: UnsafeMutableRawBufferPointer) throws {
        guard let symbolOpcode = state.symbolOpcode else {
            throw MachOError.malformed("a bind comes before any symbol")
        }
        let segment = try segment(for: state)
        guard segment.vmSize >= MachO.pointerSize, state.offset <= segment.vmSize - MachO.pointerSize,
            segment.vmAddress >= imageBase
        else {
            throw MachOError.malformed("a bind of \(state.symbol) lies outside segment \(segment.name)")
        }
        if state.ordinal > 0 {
            guard state.ordinal <= libraries.count else {
                throw MachOError.malformed("\(state.symbol) is bound from library \(state.ordinal), which isn't linked")
            }
            if libraries[state.ordinal - 1].isWeak {
                image[symbolOpcode] |= MachO.symbolFlagWeakImport
            }
        }
        if state.isRedirected, state.type == BindState.pointerType {
            slots[state.symbol, default: []].append(segment.vmAddress - imageBase + state.offset)
        }
    }
}
