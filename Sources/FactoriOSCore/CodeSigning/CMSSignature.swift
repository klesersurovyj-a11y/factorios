import Crypto
import Foundation
import SwiftASN1

/// Builds the detached CMS SignedData over a CodeDirectory, in the shape Apple's `codesign` produces.
enum CMSSignature {
    private enum OID {
        static let data: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 7, 1]
        static let signedData: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 7, 2]
        static let sha256: ASN1ObjectIdentifier = [2, 16, 840, 1, 101, 3, 4, 2, 1]
        static let rsaEncryption: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 1, 1]
        static let contentType: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 9, 3]
        static let messageDigest: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 9, 4]
        static let signingTime: ASN1ObjectIdentifier = [1, 2, 840, 113_549, 1, 9, 5]
        static let appleCDHashes: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 9, 1]
        static let appleCDHash2: ASN1ObjectIdentifier = [1, 2, 840, 113_635, 100, 9, 2]
    }

    /// Apple's legacy CDHashes attribute is a plist listing each CodeDirectory hash cut to 20 bytes.
    private static let truncatedCDHashSize = 20
    private static let implicitZero = ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific)

    /// Signs `codeDirectory` with `identity` and returns the DER ContentInfo.
    static func make(codeDirectory: [UInt8], identity: any SigningIdentity, signingTime: Date) throws -> [UInt8] {
        let chain = identity.certificateChain
        guard let leaf = chain.first else {
            throw SigningError.emptyCertificateChain
        }
        let signer = try SignerIdentifier(certificate: leaf)
        let cdHash = CodeSignatureBlobs.sha256(codeDirectory)
        let time = try utcTime(signingTime)
        do {
            let attributes = try signedAttributes(cdHash: cdHash, time: time)
            var signedBytes = DER.Serializer()
            try signedBytes.serializeSetOf(attributes)
            let signature: Data
            do {
                signature = try identity.sign(sha256RSA: Data(signedBytes.serializedBytes))
            } catch {
                throw SigningError.signingFailed(error.localizedDescription)
            }
            var serializer = DER.Serializer()
            try serializer.appendConstructedNode(identifier: .sequence) { contentInfo in
                try contentInfo.serialize(OID.signedData)
                try contentInfo.serialize(explicitlyTaggedWithTagNumber: 0, tagClass: .contextSpecific) { explicit in
                    try serializeSignedData(
                        into: &explicit, chain: chain, signer: signer, attributes: attributes, signature: signature)
                }
            }
            return serializer.serializedBytes
        } catch let error as SigningError {
            throw error
        } catch {
            throw SigningError.encodingFailed(String(describing: error))
        }
    }

    private static func serializeSignedData(
        into coder: inout DER.Serializer,
        chain: [Data],
        signer: SignerIdentifier,
        attributes: [RawDER],
        signature: Data
    ) throws {
        try coder.appendConstructedNode(identifier: .sequence) { signedData in
            try signedData.serialize(1)
            try signedData.appendConstructedNode(identifier: .set) { try serializeSHA256Algorithm(into: &$0) }
            try signedData.appendConstructedNode(identifier: .sequence) { try $0.serialize(OID.data) }
            // [0] IMPLICIT SET OF Certificate: serializeSetOf sorts the encodings as DER (X.690 11.6) requires.
            try signedData.serializeSetOf(chain.map { RawDER(bytes: Array($0)) }, identifier: implicitZero)
            try signedData.appendConstructedNode(identifier: .set) { signerInfos in
                try signerInfos.appendConstructedNode(identifier: .sequence) { signerInfo in
                    try signerInfo.serialize(1)
                    signerInfo.appendConstructedNode(identifier: .sequence) { sid in
                        sid.serializeRawBytes(signer.issuer)
                        sid.serializeRawBytes(signer.serialNumber)
                    }
                    try serializeSHA256Algorithm(into: &signerInfo)
                    try signerInfo.serializeSetOf(attributes, identifier: implicitZero)
                    try signerInfo.appendConstructedNode(identifier: .sequence) { algorithm in
                        try algorithm.serialize(OID.rsaEncryption)
                        try algorithm.serialize(ASN1Null())
                    }
                    try signerInfo.serialize(ASN1OctetString(contentBytes: ArraySlice(signature)))
                }
            }
        }
    }

    private static func serializeSHA256Algorithm(into coder: inout DER.Serializer) throws {
        try coder.appendConstructedNode(identifier: .sequence) { algorithm in
            try algorithm.serialize(OID.sha256)
            try algorithm.serialize(ASN1Null())
        }
    }

    /// contentType, signingTime, messageDigest and Apple's two CDHash attributes.
    private static func signedAttributes(cdHash: [UInt8], time: UTCTime) throws -> [RawDER] {
        let cdHashesPlist = try cdHashesPropertyList(cdHash: cdHash)
        return [
            try attribute(OID.contentType) { try $0.serialize(OID.data) },
            try attribute(OID.signingTime) { try $0.serialize(time) },
            try attribute(OID.messageDigest) { try $0.serialize(ASN1OctetString(contentBytes: cdHash[...])) },
            try attribute(OID.appleCDHashes) { try $0.serialize(ASN1OctetString(contentBytes: cdHashesPlist[...])) },
            try attribute(OID.appleCDHash2) { values in
                try values.appendConstructedNode(identifier: .sequence) { hash in
                    try hash.serialize(OID.sha256)
                    try hash.serialize(ASN1OctetString(contentBytes: cdHash[...]))
                }
            },
        ]
    }

    /// `SEQUENCE { type, SET { values } }`.
    private static func attribute(
        _ type: ASN1ObjectIdentifier, values: (inout DER.Serializer) throws -> Void
    ) throws -> RawDER {
        var serializer = DER.Serializer()
        try serializer.appendConstructedNode(identifier: .sequence) { attribute in
            try attribute.serialize(type)
            try attribute.appendConstructedNode(identifier: .set) { try values(&$0) }
        }
        return RawDER(bytes: serializer.serializedBytes)
    }

    /// The XML plist `{ cdhashes = [ <first 20 bytes of the CodeDirectory hash> ] }`.
    private static func cdHashesPropertyList(cdHash: [UInt8]) throws -> [UInt8] {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let plist = CDHashesPlist(cdhashes: [Data(cdHash.prefix(truncatedCDHashSize))])
        return Array(try encoder.encode(plist))
    }

    private static func utcTime(_ date: Date) throws -> UTCTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        do {
            return try UTCTime(
                year: parts.year ?? 0,
                month: parts.month ?? 0,
                day: parts.day ?? 0,
                hours: parts.hour ?? 0,
                minutes: parts.minute ?? 0,
                seconds: parts.second ?? 0
            )
        } catch {
            throw SigningError.invalidSigningTime
        }
    }
}

/// The plist body of Apple's CDHashes attribute.
private struct CDHashesPlist: Encodable {
    let cdhashes: [Data]
}

/// Already-encoded DER, serialized as is.
private struct RawDER: DERSerializable {
    let bytes: [UInt8]

    func serialize(into coder: inout DER.Serializer) {
        coder.serializeRawBytes(bytes)
    }
}

/// The issuer and serial number of the leaf certificate, as CMS's IssuerAndSerialNumber needs them.
private struct SignerIdentifier {
    /// The DER issuer Name.
    let issuer: ArraySlice<UInt8>
    /// The DER serial number INTEGER.
    let serialNumber: ArraySlice<UInt8>

    /// Reads `Certificate.tbsCertificate`'s serialNumber and issuer.
    init(certificate: Data) throws {
        let root: ASN1Node
        do {
            root = try DER.parse(Array(certificate))
        } catch {
            throw SigningError.invalidCertificate
        }
        guard root.identifier == .sequence, case .constructed(let certificateFields) = root.content,
            let tbs = certificateFields.first(where: { _ in true }), tbs.identifier == .sequence,
            case .constructed(let tbsFields) = tbs.content
        else {
            throw SigningError.invalidCertificate
        }
        var fields = tbsFields.makeIterator()
        var serialCandidate = fields.next()
        if serialCandidate?.identifier == ASN1Identifier(tagWithNumber: 0, tagClass: .contextSpecific) {
            serialCandidate = fields.next()  // the optional explicit version
        }
        let signatureAlgorithm = fields.next()
        guard let serial = serialCandidate, serial.identifier == .integer, signatureAlgorithm?.identifier == .sequence,
            let issuerNode = fields.next(), issuerNode.identifier == .sequence
        else {
            throw SigningError.invalidCertificate
        }
        self.issuer = issuerNode.encodedBytes
        self.serialNumber = serial.encodedBytes
    }
}
