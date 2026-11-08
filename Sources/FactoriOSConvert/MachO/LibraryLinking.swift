/// How each library reference changes on the way from macOS to iOS.
enum LibraryLinking {
    /// Libraries every iOS process has with the symbols the game uses; they stay required.
    ///
    /// Everything else may be missing or trimmed on iOS and becomes weak.
    static let requiredLibraries: Set<String> = [
        "/usr/lib/libSystem.B.dylib",
        "/usr/lib/libobjc.A.dylib",
        "/usr/lib/libc++.1.dylib",
        "/usr/lib/libresolv.9.dylib",
        "/System/Library/Frameworks/Foundation.framework/Foundation",
        "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation",
    ]

    /// Mac frameworks whose used symbols live in an iOS system library.
    ///
    /// The command remains weak so unrelated framework symbols may stay absent. CoreServices supplies `nan` to the
    /// demo's initializers; libSystem exports it on iOS, letting dyld resolve that call before the post-dlopen
    /// compatibility slots can be filled.
    static let weakRedirects = [
        "/System/Library/Frameworks/CoreServices.framework/CoreServices": "/usr/lib/libSystem.B.dylib"
    ]

    /// Rewrites macOS's versioned bundle layout `…/X.framework/Versions/<V>/X` to iOS's flat `…/X.framework/X`.
    ///
    /// Paths of any other form are returned unchanged.
    static func flattenedPath(_ path: String) -> String {
        var components = path.split(separator: "/", omittingEmptySubsequences: false)
        let count = components.count
        guard count >= 4 else {
            return path
        }
        let bundle = components[count - 4]
        let name = components[count - 1]
        guard components[count - 3] == "Versions", !name.isEmpty, bundle == "\(name).framework" else {
            return path
        }
        components.removeSubrange(count - 3..<count - 1)
        return components.joined(separator: "/")
    }
}

/// A library reference as it will appear in the converted image.
struct ConvertedLibrary {
    let original: LinkedLibrary
    let path: String
    let type: UInt32

    /// Whether dyld may leave this library out, which makes every symbol bound from it a weak import.
    var isWeak: Bool {
        type == LoadCommandType.loadWeakDylib
    }

    init(_ library: LinkedLibrary) {
        original = library
        let flattened = LibraryLinking.flattenedPath(library.path)
        path = LibraryLinking.weakRedirects[flattened] ?? flattened
        // A redirected library is never in requiredLibraries, so it stays weak.
        type = LibraryLinking.requiredLibraries.contains(flattened) ? library.type : LoadCommandType.loadWeakDylib
    }
}
