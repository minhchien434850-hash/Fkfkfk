import Foundation
import Security

/// RSA-4096 key pair for asymmetric key exchange (wrap the AES session key).
/// Uses OAEP-SHA256 padding via the Security framework.
final class RSAKeyService {
    private var privateKey: SecKey?
    private(set) var publicKey: SecKey?

    func generateKeyPair() throws {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 4096,
        ]
        var error: Unmanaged<CFError>?
        guard let priv = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw RemoteError.unknown("RSA key generation failed")
        }
        privateKey = priv
        publicKey = SecKeyCopyPublicKey(priv)
    }

    func encrypt(_ data: Data) throws -> Data {
        guard let publicKey else { throw RemoteError.unknown("Missing public key") }
        var error: Unmanaged<CFError>?
        guard let cipher = SecKeyCreateEncryptedData(
            publicKey, .rsaEncryptionOAEPSHA256, data as CFData, &error) as Data? else {
            throw RemoteError.unknown("RSA encryption failed")
        }
        return cipher
    }

    func decrypt(_ data: Data) throws -> Data {
        guard let privateKey else { throw RemoteError.unknown("Missing private key") }
        var error: Unmanaged<CFError>?
        guard let plain = SecKeyCreateDecryptedData(
            privateKey, .rsaEncryptionOAEPSHA256, data as CFData, &error) as Data? else {
            throw RemoteError.unknown("RSA decryption failed")
        }
        return plain
    }

    /// External representation of the public key (to send to the agent).
    func exportPublicKey() -> Data? {
        guard let publicKey else { return nil }
        return SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
    }
}
