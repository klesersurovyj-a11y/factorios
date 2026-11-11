/// Values from `<mach-o/loader.h>`, `<mach-o/fat.h>` and `<mach/machine.h>`.
enum MachO {
    static let fatMagic: UInt32 = 0xCAFE_BABE
    static let magic64: UInt32 = 0xFEED_FACF
    static let cpuTypeARM64: UInt32 = 0x0100_000C

    static let headerSize = 32
    static let pointerSize: UInt64 = 8
    static let pageSize: UInt64 = 0x4000

    static let fileTypeExecute: UInt32 = 0x2
    static let fileTypeDylib: UInt32 = 0x6
    static let flagNoReexportedDylibs: UInt32 = 0x0010_0000
    static let flagPIE: UInt32 = 0x0020_0000

    static let platformIOS: UInt32 = 2
    static let platformIOSSimulator: UInt32 = 7
    static let symbolFlagWeakImport: UInt8 = 0x1

    /// `LC_BUILD_VERSION` minimum OS, iOS 17.0, in the `xxxx.yy.zz` nibble encoding.
    static let minimumIOS: UInt32 = 0x11_0000
    /// `LC_BUILD_VERSION` SDK, iOS 18.0.
    static let iOSSDK: UInt32 = 0x12_0000
}

/// Load command identifiers (`LC_*`).
enum LoadCommandType {
    static let segment64: UInt32 = 0x19
    static let symtab: UInt32 = 0x2
    static let dysymtab: UInt32 = 0xB
    static let loadDylib: UInt32 = 0xC
    static let idDylib: UInt32 = 0xD
    static let loadDylinker: UInt32 = 0xE
    static let loadWeakDylib: UInt32 = 0x8000_0018
    static let reexportDylib: UInt32 = 0x8000_001F
    static let lazyLoadDylib: UInt32 = 0x20
    static let loadUpwardDylib: UInt32 = 0x8000_0023
    static let codeSignature: UInt32 = 0x1D
    static let segmentSplitInfo: UInt32 = 0x1E
    static let dyldInfo: UInt32 = 0x22
    static let dyldInfoOnly: UInt32 = 0x8000_0022
    static let functionStarts: UInt32 = 0x26
    static let dataInCode: UInt32 = 0x29
    static let dylibCodeSignDRs: UInt32 = 0x2B
    static let linkerOptimizationHint: UInt32 = 0x2E
    static let buildVersion: UInt32 = 0x32
    static let dyldExportsTrie: UInt32 = 0x8000_0033
    static let dyldChainedFixups: UInt32 = 0x8000_0034

    /// Commands that name a library the image links against; their order defines bind ordinals.
    static let libraryReferences: Set<UInt32> = [
        loadDylib, loadWeakDylib, reexportDylib, lazyLoadDylib, loadUpwardDylib,
    ]
    /// `linkedit_data_command`s: `{ cmd, cmdsize, dataoff, datasize }` pointing into `__LINKEDIT`.
    static let linkeditData: Set<UInt32> = [
        segmentSplitInfo, functionStarts, dataInCode, dylibCodeSignDRs, linkerOptimizationHint,
        dyldExportsTrie, dyldChainedFixups,
    ]
}

/// Bind opcodes (`BIND_OPCODE_*`): the high nibble of each opcode byte.
enum BindOpcode {
    static let mask: UInt8 = 0xF0
    static let immediateMask: UInt8 = 0x0F

    static let done: UInt8 = 0x00
    static let setDylibOrdinalImm: UInt8 = 0x10
    static let setDylibOrdinalULEB: UInt8 = 0x20
    static let setDylibSpecialImm: UInt8 = 0x30
    static let setSymbolTrailingFlagsImm: UInt8 = 0x40
    static let setTypeImm: UInt8 = 0x50
    static let setAddendSLEB: UInt8 = 0x60
    static let setSegmentAndOffsetULEB: UInt8 = 0x70
    static let addAddrULEB: UInt8 = 0x80
    static let doBind: UInt8 = 0x90
    static let doBindAddAddrULEB: UInt8 = 0xA0
    static let doBindAddAddrImmScaled: UInt8 = 0xB0
    static let doBindULEBTimesSkippingULEB: UInt8 = 0xC0
    static let threaded: UInt8 = 0xD0
}
