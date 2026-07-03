import Foundation

/// Minimal JWT payload decoder (OAuth2/OIDC access tokens).
/// Only reads claims for expiry/refresh decisions; signature verification is
/// performed server-side.
enum JWT {
    static func decodePayload(_ token: String) -> [String: Any]? {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    /// True when the token is expired (or within `leeway` seconds of expiry).
    static func isExpired(_ token: String, leeway: TimeInterval = 30, now: Date = Date()) -> Bool {
        guard let payload = decodePayload(token), let exp = payload["exp"] as? Double else { return false }
        return now.timeIntervalSince1970 + leeway >= exp
    }
}
