import Foundation
import CryptoKit

/// AES-256-GCM authenticated encryption using CryptoKit.
/// Used to seal control/clipboard payloads with a per-session symmetric key.
final class CryptoService: SecureCryptoProtocol {

    func seal(_ plaintext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let box = try AES.GCM.seal(plaintext, using: symmetricKey)
        guard let combined = box.combined else { throw RemoteError.unknown("GCM seal failed") }
        return combined
    }

    func open(_ ciphertext: Data, key: Data) throws -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: symmetricKey)
    }

    /// Generates a fresh 256-bit session key.
    static func randomKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// SHA-256 of arbitrary data (used for file integrity checks).
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
