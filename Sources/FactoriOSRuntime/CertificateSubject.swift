import Foundation

/// Reads the subject's organizational unit (the Apple team identifier) from a DER X.509 certificate.
///
/// iOS has no public API for subject attributes other than the common name, so this walks the few DER structures on
/// the way: Certificate → TBSCertificate → subject Name → RelativeDistinguishedName → AttributeTypeAndValue.
enum CertificateSubject {
    private static let sequenceTag: UInt8 = 0x30
    private static let setTag: UInt8 = 0x31
    private static let objectIdentifierTag: UInt8 = 0x06
    private static let versionTag: UInt8 = 0xA0
    private static let bmpStringTag: UInt8 = 0x1E
    /// id-at-organizationalUnitName, 2.5.4.11.
    private static let organizationalUnitOID: [UInt8] = [0x55, 0x04, 0x0B]

    /// The first organizational unit of the certificate's subject, or nil when there is none or the DER is malformed.
    static func organizationalUnit(ofCertificate certificate: Data) -> String? {
        try? findOrganizationalUnit([UInt8](certificate)[...])
    }

    private static func findOrganizationalUnit(_ certificate: ArraySlice<UInt8>) throws -> String? {
        var names = DERReader(try subjectName(ofCertificate: certificate))
        while !names.isAtEnd {
            var attributes = DERReader(try names.next(expecting: setTag).contents)
            while !attributes.isAtEnd {
                var fields = DERReader(try attributes.next(expecting: sequenceTag).contents)
                let type = try fields.next(expecting: objectIdentifierTag)
                let value = try fields.next()
                if Array(type.contents) == organizationalUnitOID {
                    return decodeString(value)
                }
            }
        }
        return nil
    }

    /// The contents of the subject Name SEQUENCE.
    private static func subjectName(ofCertificate bytes: ArraySlice<UInt8>) throws -> ArraySlice<UInt8> {
        var outer = DERReader(bytes)
        var certificate = DERReader(try outer.next(expecting: sequenceTag).contents)
        var tbs = DERReader(try certificate.next(expecting: sequenceTag).contents)
        // An optional explicit version, the serial number, the signature algorithm, the issuer, the validity, and
        // then the subject.
        if try tbs.next().tag == versionTag {
            _ = try tbs.next()
        }
        for _ in 0..<3 {
            _ = try tbs.next()
        }
        return try tbs.next(expecting: sequenceTag).contents
    }

    private static func decodeString(_ element: DERReader.Element) -> String? {
        if element.tag == bmpStringTag {
            let bytes = Array(element.contents)
            let units = stride(from: 0, to: bytes.count - 1, by: 2).map { index in
                UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
            }
            return String(utf16CodeUnits: units, count: units.count)
        }
        // UTF8String, PrintableString and IA5String are all UTF-8 compatible.
        return String(bytes: element.contents, encoding: .utf8)
    }
}

/// Malformed DER.
private struct DERError: Error {}

/// Splits DER bytes into tag-length-value elements.
private struct DERReader {
    /// One element: its tag byte and its contents.
    struct Element {
        let tag: UInt8
        let contents: ArraySlice<UInt8>
    }

    private var bytes: ArraySlice<UInt8>

    /// Whether every element has been read.
    var isAtEnd: Bool { bytes.isEmpty }

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
    }

    /// The next element, which must have `tag`.
    mutating func next(expecting tag: UInt8) throws -> Element {
        let element = try next()
        guard element.tag == tag else {
            throw DERError()
        }
        return element
    }

    /// The next element.
    mutating func next() throws -> Element {
        guard bytes.count >= 2, let tag = bytes.first else {
            throw DERError()
        }
        var index = bytes.startIndex + 1
        let first = Int(bytes[index])
        index += 1
        var length = first
        if first & 0x80 != 0 {
            let count = first & 0x7F
            guard count >= 1, count <= 4, bytes.endIndex - index >= count else {
                throw DERError()
            }
            length = bytes[index..<index + count].reduce(0) { value, byte in value << 8 | Int(byte) }
            index += count
        }
        guard bytes.endIndex - index >= length else {
            throw DERError()
        }
        let element = Element(tag: tag, contents: bytes[index..<index + length])
        bytes = bytes[(index + length)...]
        return element
    }
}
