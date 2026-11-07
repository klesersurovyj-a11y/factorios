import Foundation
import SwiftASN1

/// Encodes an entitlements property list in Apple's DER form (the `0xfade7172` blob iOS checks since iOS 15).
///
/// The layout is `[APPLICATION 16] { INTEGER 1, dictionary }`, where a dictionary is a `[CONTEXT 16]` set of
/// `SEQUENCE { UTF8String key, value }` sorted by key, an array a SEQUENCE, and strings, integers and booleans
/// their universal ASN.1 types.
enum DEREntitlements {
    private static let version = 1
    private static let rootIdentifier = ASN1Identifier(tagWithNumber: 16, tagClass: .application)

    /// The DER encoding of the XML or binary property list `plist`, whose root must be a dictionary.
    static func encode(_ plist: Data) throws -> [UInt8] {
        let root: EntitlementValue
        do {
            root = try PropertyListDecoder().decode(EntitlementValue.self, from: plist)
        } catch {
            throw SigningError.invalidEntitlements
        }
        guard case .dictionary = root else {
            throw SigningError.invalidEntitlements
        }
        do {
            var serializer = DER.Serializer()
            try serializer.appendConstructedNode(identifier: rootIdentifier) { body in
                try body.serialize(version)
                try body.serialize(root)
            }
            return serializer.serializedBytes
        } catch {
            throw SigningError.encodingFailed(String(describing: error))
        }
    }
}

/// One value of an entitlements property list.
private enum EntitlementValue: Decodable, DERSerializable {
    case bool(Bool)
    case integer(Int)
    case string(String)
    case array([Self])
    case dictionary([String: Self])

    private static let dictionaryIdentifier = ASN1Identifier(tagWithNumber: 16, tagClass: .contextSpecific)

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Self].self) {
            self = .array(value)
        } else {
            self = .dictionary(try container.decode([String: Self].self))
        }
    }

    func serialize(into coder: inout DER.Serializer) throws {
        switch self {
        case .bool(let value):
            try coder.serialize(value)
        case .integer(let value):
            try coder.serialize(value)
        case .string(let value):
            try coder.serialize(ASN1UTF8String(value))
        case .array(let values):
            try coder.serializeSequenceOf(values)
        case .dictionary(let entries):
            let sorted = entries.sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            try coder.appendConstructedNode(identifier: Self.dictionaryIdentifier) { dictionary in
                for (key, value) in sorted {
                    try dictionary.appendConstructedNode(identifier: .sequence) { pair in
                        try pair.serialize(ASN1UTF8String(key))
                        try pair.serialize(value)
                    }
                }
            }
        }
    }
}
