public import Foundation

/// Signs a thin arm64 Mach-O with a real (not ad-hoc) embedded code signature.
public enum MachOSigner {
    /// The signature's file offset alignment.
    private static let signatureAlignment = 16
    /// Room for the CMS structure, signed attributes and RSA signature beyond the certificates themselves; an
    /// 8192-bit RSA signature and the attributes take well under half of it.
    private static let cmsOverhead = 4_096

    /// Signs `image` with a real, not ad-hoc, embedded code signature.
    ///
    /// Ad-hoc-free, real signature: CodeDirectory (SHA-256, 4 KiB pages, version 0x20400 with execSeg fields from
    /// __TEXT, flags 0), empty requirement set, optional entitlements, CMS SignedData (detached, SHA-256 digest,
    /// signed attributes: contentType, signingTime, messageDigest, Apple's CDHashes plist attribute
    /// 1.2.840.113635.100.9.1 and CDHash2 attribute 1.2.840.113635.100.9.2), SuperBlob 0xfade0cc0.
    /// Inserts or reuses LC_CODE_SIGNATURE, pads __LINKEDIT, appends the blob 16-byte aligned.
    ///
    /// - Parameters:
    ///   - image: A thin arm64 Mach-O; an existing signature at the end of the file is replaced.
    ///   - identifier: The code signing identifier written into the CodeDirectory.
    ///   - identity: The certificate chain and key that sign the CodeDirectory.
    ///   - entitlements: An entitlements property list, embedded as XML and DER blobs when given.
    /// - Returns: The signed image.
    /// - Throws: `SigningError` when the image can't be parsed or edited, the entitlements or certificate can't be
    ///   read, or the identity fails to sign.
    public static func sign(
        _ image: Data, identifier: String, identity: any SigningIdentity, entitlements: Data? = nil
    ) throws -> Data {
        let layout = try MachOSignatureLayout.parse(image)
        let codeEnd = layout.codeEnd(imageSize: image.count)
        let signatureOffset = align(codeEnd, to: signatureAlignment)

        let extraBlobs = try entitlementBlobs(entitlements)
        let codeDirectory = CodeDirectory(
            identifier: identifier,
            teamIdentifier: identity.teamIdentifier,
            specialSlotHashes: specialSlotHashes(entitlementBlobs: extraBlobs),
            executableSegmentBase: layout.text.fileOffset,
            executableSegmentLimit: layout.text.fileSize
        )
        let certificatesSize = identity.certificateChain.reduce(0) { $0 + $1.count }
        let cmsReserve = CodeSignatureBlobs.blobHeaderSize + certificatesSize + cmsOverhead
        let blobSizes =
            [codeDirectory.size(codeLimit: signatureOffset), CodeSignatureBlobs.emptyRequirements.count]
            + extraBlobs.map(\.blob.count) + [cmsReserve]
        let reserved = align(CodeSignatureBlobs.superBlobSize(blobSizes: blobSizes), to: signatureAlignment)
        guard signatureOffset + reserved <= Int(UInt32.max) else {
            throw SigningError.imageTooLarge
        }

        var signed = Data(capacity: signatureOffset + reserved)
        signed.append(image[image.startIndex..<(image.startIndex + codeEnd)])
        signed.append(Data(count: signatureOffset - codeEnd))
        try layout.writeSignatureCommand(into: &signed, dataOffset: signatureOffset, dataSize: reserved)

        let directory = codeDirectory.encode(code: signed, codeLimit: signatureOffset)
        let cms = try CMSSignature.make(codeDirectory: directory, identity: identity, signingTime: Date())
        let superBlob = CodeSignatureBlobs.superBlob(
            [
                .init(slot: CodeSignatureBlobs.Slot.codeDirectory, blob: directory),
                .init(slot: CodeSignatureBlobs.Slot.requirements, blob: CodeSignatureBlobs.emptyRequirements),
            ]
                + extraBlobs
                + [
                    .init(
                        slot: CodeSignatureBlobs.Slot.cmsSignature,
                        blob: CodeSignatureBlobs.blob(magic: CodeSignatureBlobs.cmsWrapperMagic, payload: cms)
                    )
                ]
        )
        guard superBlob.count <= reserved else {
            throw SigningError.signatureTooLarge(bytes: superBlob.count)
        }
        signed.append(contentsOf: superBlob)
        signed.append(Data(count: reserved - superBlob.count))
        return signed
    }

    /// The XML and DER entitlements blobs, or none without entitlements.
    private static func entitlementBlobs(_ entitlements: Data?) throws -> [CodeSignatureBlobs.Entry] {
        guard let entitlements else {
            return []
        }
        let der = try DEREntitlements.encode(entitlements)
        return [
            .init(
                slot: CodeSignatureBlobs.Slot.entitlements,
                blob: CodeSignatureBlobs.blob(magic: CodeSignatureBlobs.entitlementsMagic, payload: entitlements)
            ),
            .init(
                slot: CodeSignatureBlobs.Slot.derEntitlements,
                blob: CodeSignatureBlobs.blob(magic: CodeSignatureBlobs.derEntitlementsMagic, payload: der)
            ),
        ]
    }

    /// Hashes for special slots -1 through -2, or through -7 with entitlements; slots without an item are zero.
    private static func specialSlotHashes(entitlementBlobs: [CodeSignatureBlobs.Entry]) -> [[UInt8]] {
        let slotCount = entitlementBlobs.map(\.slot).max() ?? CodeSignatureBlobs.Slot.requirements
        var hashes = [[UInt8]](repeating: [UInt8](repeating: 0, count: CodeDirectory.hashSize), count: Int(slotCount))
        let items =
            [
                CodeSignatureBlobs.Entry(
                    slot: CodeSignatureBlobs.Slot.requirements, blob: CodeSignatureBlobs.emptyRequirements)
            ] + entitlementBlobs
        for item in items {
            hashes[Int(item.slot) - 1] = CodeSignatureBlobs.sha256(item.blob)
        }
        return hashes
    }

    private static func align(_ value: Int, to alignment: Int) -> Int {
        (value + alignment - 1) / alignment * alignment
    }
}
