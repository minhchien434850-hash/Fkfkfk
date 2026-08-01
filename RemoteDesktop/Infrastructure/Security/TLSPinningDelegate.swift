import Foundation
import CryptoKit

/// Certificate/public-key pinning delegate for `URLSession`.
/// Provide SHA-256 public-key pins (base64). When empty it falls back to the
/// system trust evaluation, so the app still works during development.
final class TLSPinningDelegate: NSObject, URLSessionDelegate {
    private let pinnedKeyHashes: Set<String>

    init(pinnedKeyHashes: Set<String> = []) { self.pinnedKeyHashes = pinnedKeyHashes }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil); return
        }
        if pinnedKeyHashes.isEmpty {
            completionHandler(.useCredential, URLCredential(trust: trust)); return
        }
        if let cert = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first,
           let key = SecCertificateCopyKey(cert),
           let data = SecKeyCopyExternalRepresentation(key, nil) as Data?,
           pinnedKeyHashes.contains(Self.sha256Base64(data)) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private static func sha256Base64(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).base64EncodedString()
    }
}
