import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

// ============================================================
//  Đăng nhập Google (OAuth 2.0 + PKCE) ngay trong app để lấy
//  Access Token (ya29...) có quyền YouTube — dùng tạo Live YouTube.
//  Dùng ASWebAuthenticationSession nên KHÔNG cần khai báo URL scheme
//  trong Info.plist (scheme callback được đăng ký động theo phiên).
// ============================================================

enum GoogleOAuthError: LocalizedError {
    case badClientID
    case cancelled
    case noCode
    case tokenExchange(String)

    var errorDescription: String? {
        switch self {
        case .badClientID:
            return "Client ID không đúng. Phải là Client ID iOS dạng …apps.googleusercontent.com"
        case .cancelled:
            return "Đã huỷ đăng nhập."
        case .noCode:
            return "Không nhận được mã uỷ quyền từ Google."
        case .tokenExchange(let m):
            return "Đổi mã lấy token thất bại: \(m)"
        }
    }
}

@MainActor
final class GoogleOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleOAuth()
    private var session: ASWebAuthenticationSession?

    struct Token {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
    }

    /// Đăng nhập và trả về access token (ya29...).
    /// - clientID: OAuth Client ID **iOS** dạng "NNN-xxxx.apps.googleusercontent.com"
    func signIn(clientID: String,
                scope: String = "https://www.googleapis.com/auth/youtube") async throws -> Token {
        let cid = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cid.hasSuffix(".apps.googleusercontent.com") else { throw GoogleOAuthError.badClientID }

        let reversed = Self.reversedClientID(cid)          // = callback scheme
        let redirectURI = "\(reversed):/oauth2redirect"
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(verifier)

        var comp = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let code = try await authorize(url: comp.url!, scheme: reversed)
        return try await exchange(code: code, clientID: cid, redirectURI: redirectURI, verifier: verifier)
    }

    /// Đăng nhập Google để LẤY DANH TÍNH (email) — trả về id_token (JWT) để gửi server xác thực.
    /// Dùng cho nút "Đăng nhập bằng Google". scope openid+email+profile.
    func signInIdToken(clientID: String) async throws -> String {
        let cid = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cid.hasSuffix(".apps.googleusercontent.com") else { throw GoogleOAuthError.badClientID }

        let reversed = Self.reversedClientID(cid)
        let redirectURI = "\(reversed):/oauth2redirect"
        let verifier = Self.randomURLSafe(64)
        let challenge = Self.codeChallenge(verifier)

        var comp = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        let code = try await authorize(url: comp.url!, scheme: reversed)
        return try await exchangeIdToken(code: code, clientID: cid, redirectURI: redirectURI, verifier: verifier)
    }

    private func exchangeIdToken(code: String, clientID: String, redirectURI: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        req.httpBody = form.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleOAuthError.tokenExchange("phản hồi không hợp lệ")
        }
        if let idToken = obj["id_token"] as? String, !idToken.isEmpty {
            return idToken
        }
        let err = (obj["error_description"] as? String) ?? (obj["error"] as? String) ?? "không rõ"
        throw GoogleOAuthError.tokenExchange(err)
    }

    private func authorize(url: URL, scheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: GoogleOAuthError.cancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let callback,
                      let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                    cont.resume(throwing: GoogleOAuthError.noCode); return
                }
                cont.resume(returning: code)
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start() {
                cont.resume(throwing: GoogleOAuthError.cancelled)
            }
        }
    }

    private func exchange(code: String, clientID: String, redirectURI: String, verifier: String) async throws -> Token {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        req.httpBody = form.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)"
        }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GoogleOAuthError.tokenExchange("phản hồi không hợp lệ")
        }
        if let token = obj["access_token"] as? String, !token.isEmpty {
            return Token(accessToken: token,
                         refreshToken: obj["refresh_token"] as? String,
                         expiresIn: (obj["expires_in"] as? Int) ?? 3600)
        }
        let err = (obj["error_description"] as? String) ?? (obj["error"] as? String) ?? "không rõ"
        throw GoogleOAuthError.tokenExchange(err)
    }

    /// Làm mới access token bằng refresh token (không cần client secret cho client iOS).
    func refresh(clientID: String, refreshToken: String) async throws -> Token {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        req.httpBody = form.map {
            "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["access_token"] as? String, !token.isEmpty else {
            throw GoogleOAuthError.tokenExchange("không làm mới được token")
        }
        return Token(accessToken: token, refreshToken: refreshToken,
                     expiresIn: (obj["expires_in"] as? Int) ?? 3600)
    }

    // MARK: - Helpers
    static func reversedClientID(_ cid: String) -> String {
        let prefix = cid.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    static func codeChallenge(_ verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(hash))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.keniosKeyWindow ?? ASPresentationAnchor()
    }
}
