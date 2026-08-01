import Foundation
import Security

/// Hardware-backed EC key stored in the Secure Enclave (device identity for
/// Zero-Trust). The private key never leaves the enclave; we sign challenges to
/// prove the device. Not available on the simulator (throws there).
final class SecureEnclaveService {
    private let tag = Data("com.kenios.remotedesktop.se.identity".utf8)

    @discardableResult
    func createKey() throws -> SecKey {
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], &acError) else {
            throw RemoteError.unknown("Access control creation failed")
        }
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ],
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw RemoteError.unknown("Secure Enclave key unavailable (device only)")
        }
        return key
    }

    func sign(_ data: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key, .ecdsaSignatureMessageX962SHA256, data as CFData, &error) as Data? else {
            throw RemoteError.unknown("Secure Enclave signing failed")
        }
        return signature
    }
}
