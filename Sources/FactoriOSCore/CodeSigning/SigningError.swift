public import Foundation

/// Why a Mach-O image couldn't be signed.
public enum SigningError: Error, LocalizedError, Equatable {
    /// The image isn't a thin 64-bit arm64 Mach-O.
    case notArm64MachO
    /// A load command runs past the load-command area or has an impossible size.
    case malformedLoadCommands
    /// The image has no segment with this name.
    case missingSegment(String)
    /// The existing LC_CODE_SIGNATURE points outside the file.
    case malformedExistingSignature
    /// `__LINKEDIT` isn't the last segment in the file, so the signature can't be appended inside it.
    case linkeditNotLast
    /// Fewer than 16 bytes of header padding are free for a new LC_CODE_SIGNATURE.
    case noRoomForSignatureCommand
    /// The signed image would pass 4 GiB, the limit of Mach-O's 32-bit signature offsets.
    case imageTooLarge
    /// The signing identity has no certificates.
    case emptyCertificateChain
    /// The leaf certificate isn't a DER X.509 certificate.
    case invalidCertificate
    /// The entitlements aren't a property-list dictionary of dictionaries, arrays, strings, integers and booleans.
    case invalidEntitlements
    /// The signing time can't be written as a CMS UTCTime (years 1950 to 2049).
    case invalidSigningTime
    /// The CMS signature couldn't be encoded.
    case encodingFailed(String)
    /// The identity couldn't produce a signature.
    case signingFailed(String)
    /// The signature, this many bytes, outgrew the space reserved for it in the image.
    case signatureTooLarge(bytes: Int)

    /// A sentence describing the failure for the player.
    public var errorDescription: String? {
        switch self {
        case .notArm64MachO:
            "The game library isn't a 64-bit ARM Mach-O."
        case .malformedLoadCommands:
            "The game library's load commands are damaged."
        case .missingSegment(let name):
            "The game library has no \(name) segment."
        case .malformedExistingSignature:
            "The game library's old code signature is damaged."
        case .linkeditNotLast:
            "The game library's __LINKEDIT segment isn't at the end of the file."
        case .noRoomForSignatureCommand:
            "The game library's header has no room for a code signature."
        case .imageTooLarge:
            "The game library is too large to sign."
        case .emptyCertificateChain:
            "The signing certificate is missing."
        case .invalidCertificate:
            "The signing certificate can't be read."
        case .invalidEntitlements:
            "The entitlements can't be encoded."
        case .invalidSigningTime:
            "The device clock is outside the range a signature can record."
        case .encodingFailed(let reason):
            "The signature couldn't be encoded: \(reason)"
        case .signingFailed(let reason):
            "The certificate's key couldn't sign the game: \(reason)"
        case .signatureTooLarge(let bytes):
            "The \(bytes)-byte signature outgrew the space reserved for it."
        }
    }
}
