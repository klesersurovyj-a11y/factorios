import FactoriOSCore
import Foundation
import Security

/// The host app's Apple Development identity, exported from macOS Keychain as PKCS#12.
///
/// The PKCS#12 file lives in `GamePaths.signingIdentity` and its password in the Keychain; Security decodes the file
/// and holds the private key, which never leaves it.
struct KeychainSigningIdentity: SigningIdentity, @unchecked Sendable {
    // @unchecked: `SecKey` is an immutable Security object that is safe to use from any thread.

    let certificateChain: [Data]
    let teamIdentifier: String
    private let privateKey: SecKey

    /// Decodes a PKCS#12 file; throws when the password is wrong or the file holds no usable identity.
    init(pkcs12: Data, password: String) throws {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(pkcs12 as CFData, options, &items)
        switch status {
        case errSecSuccess:
            break
        case errSecAuthFailed, errSecPkcs12VerifyFailure:
            throw SigningIdentityError.wrongPassword
        default:
            throw SigningIdentityError.unreadable(status: status)
        }
        guard let item = (items as? [[String: Any]])?.first,
            let identity = Self.cast(
                item[kSecImportItemIdentity as String],
                typeID: SecIdentityGetTypeID(),
                to: SecIdentity.self
            )
        else {
            throw SigningIdentityError.noIdentity
        }
        var key: SecKey?
        var leaf: SecCertificate?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key,
            SecIdentityCopyCertificate(identity, &leaf) == errSecSuccess, let leaf
        else {
            throw SigningIdentityError.noIdentity
        }
        guard SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw SigningIdentityError.unsupportedKey
        }
        let leafData = SecCertificateCopyData(leaf) as Data
        guard let team = CertificateSubject.organizationalUnit(ofCertificate: leafData) else {
            throw SigningIdentityError.noTeamIdentifier
        }
        let chain = (item[kSecImportItemCertChain as String] as? [AnyObject] ?? [])
            .compactMap { Self.cast($0, typeID: SecCertificateGetTypeID(), to: SecCertificate.self) }
            .map { SecCertificateCopyData($0) as Data }
        certificateChain = [leafData] + chain.filter { $0 != leafData }
        teamIdentifier = team
        privateKey = key
    }

    /// The imported identity; throws `SigningIdentityError.notImported` before one was imported.
    static func load(paths: GamePaths) throws -> Self {
        guard let password = try SigningPasswordStore.password(),
            let pkcs12 = try? Data(contentsOf: paths.signingIdentity)
        else {
            throw SigningIdentityError.notImported
        }
        return try Self(pkcs12: pkcs12, password: password)
    }

    func sign(sha256RSA message: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &error
            )
        else {
            let reason = error.map { ($0.takeRetainedValue() as any Error).localizedDescription } ?? "unknown error"
            throw SigningIdentityError.signingFailed(reason)
        }
        return signature as Data
    }

    /// A Core Foundation object from a Security dictionary as `type`, checked by its type ID.
    private static func cast<T>(_ value: Any?, typeID: CFTypeID, to type: T.Type) -> T? {
        guard let value, CFGetTypeID(value as AnyObject) == typeID else {
            // Missing, or a different Core Foundation type.
            return nil
        }
        return unsafeBitCast(value as AnyObject, to: type)
    }
}

/// The PKCS#12 password in the Keychain, readable only on this device after its first unlock.
enum SigningPasswordStore {
    private static let service = "FactoriOS.signing-identity"
    private static let account = "identity.p12"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Replaces the stored password.
    static func save(_ password: String) throws {
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SigningIdentityError.keychain(status: status)
        }
    }

    /// The stored password, or nil when none is stored.
    static func password() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }
        case errSecItemNotFound:
            return nil
        default:
            throw SigningIdentityError.keychain(status: status)
        }
    }
}
