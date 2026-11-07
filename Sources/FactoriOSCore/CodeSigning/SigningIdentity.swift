public import Foundation

/// A certificate and private key that can sign code for this device.
///
/// The runtime provides one backed by the Keychain (the Apple Development identity exported from the developer's
/// Mac as PKCS#12); the signer only needs the certificates and an RSA signing primitive, so it stays portable.
public protocol SigningIdentity: Sendable {
    /// The DER-encoded certificate chain, leaf first (Apple's WWDR intermediate included if available).
    var certificateChain: [Data] { get }
    /// The team identifier: the organizational unit of the leaf certificate's subject.
    var teamIdentifier: String { get }
    /// Signs `message` with PKCS#1 v1.5 RSA over its SHA-256 digest.
    ///
    /// - Parameter message: The bytes to sign; the identity hashes them itself.
    /// - Returns: The raw RSA signature.
    /// - Throws: Whatever error the key store reports when the key can't sign.
    func sign(sha256RSA message: Data) throws -> Data
}
