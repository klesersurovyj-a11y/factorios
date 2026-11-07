import Foundation

/// Why the Apple Development identity couldn't be imported or used.
enum SigningIdentityError: Error, LocalizedError, Equatable {
    /// No certificate was imported yet.
    case notImported
    /// The PKCS#12 password is wrong.
    case wrongPassword
    /// The file isn't a PKCS#12 that Security can read.
    case unreadable(status: OSStatus)
    /// The PKCS#12 has no certificate with its private key.
    case noIdentity
    /// The private key can't make PKCS#1 v1.5 SHA-256 RSA signatures, which code signing needs.
    case unsupportedKey
    /// The certificate's subject has no organizational unit, which is where Apple puts the team identifier.
    case noTeamIdentifier
    /// The Keychain refused to store or read the password.
    case keychain(status: OSStatus)
    /// Security failed to sign.
    case signingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notImported:
            "Import the Apple Development identity (.p12) used to provision FactoriOS first."
        case .wrongPassword:
            "The certificate's password is wrong."
        case .unreadable(let status):
            "The certificate file can't be read (error \(status))."
        case .noIdentity:
            "The certificate file has no private key."
        case .unsupportedKey:
            "The certificate's key isn't an RSA key that can sign code."
        case .noTeamIdentifier:
            "The certificate has no team identifier."
        case .keychain(let status):
            "The Keychain refused the certificate's password (error \(status))."
        case .signingFailed(let reason):
            "Signing failed: \(reason)"
        }
    }
}
