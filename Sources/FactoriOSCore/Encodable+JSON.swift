public import Foundation

public extension Encodable {
    /// Writes `self` as JSON to `file` in one step, creating its folder.
    func writeJSON(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

public extension Decodable {
    /// The value saved in `file`; `nil` when there is none or it can't be read.
    static func readJSON(from file: URL) -> Self? {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }
}
