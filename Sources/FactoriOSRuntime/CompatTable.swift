import FactoriOSCompat

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
        return result
    }

    /// The symbols whose slots the converter records.
    static func symbols() -> Set<String> {
        Set(replacements().keys)
    }
}
