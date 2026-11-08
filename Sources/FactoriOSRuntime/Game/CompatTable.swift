import FactoriOSCompat
import FactoriOSCore

/// The compatibility layer's replacement table (FOSCompatReplacements) in Swift form.
enum CompatTable {
    /// Mach-O symbol name → the address the game's slots for it must hold.
    static func replacements() -> [String: UnsafeRawPointer] {
        var count = 0
        let table = FOSCompatReplacements(&count)
        var result: [String: UnsafeRawPointer] = [:]
        for index in 0..<count {
            let entry = table[index]
            result[String(cString: entry.symbol)] = entry.replacement
        }
        // A library converted on a Mac records the slots of GameLibrary.redirectedSymbols; any symbol the two lists
        // disagree on would go unpatched or unresolved.
        precondition(
            Set(result.keys) == GameLibrary.redirectedSymbols,
            "FOSCompatReplacements and GameLibrary.redirectedSymbols differ"
        )
        return result
    }
}
