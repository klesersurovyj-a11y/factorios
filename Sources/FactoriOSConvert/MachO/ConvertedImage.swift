import FactoriOSCore
import Foundation

/// The game executable turned into an unsigned iOS library.
struct ConvertedImage: Sendable {
    /// A thin arm64 `MH_DYLIB` without code signature, with header room for `LC_CODE_SIGNATURE`.
    let data: Data
    /// The pointer slots of the redirected symbols.
    let manifest: SymbolSlotManifest
}
