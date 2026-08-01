import Foundation
import AuthenticationServices
import UIKit

// ============================================================
//  Đăng nhập Facebook (OAuth 2.0, luồng token cho app native) để lấy
//  Access Token có quyền tạo Live. Dùng ASWebAuthenticationSession,
//  callback scheme = fb<APP_ID> (không cần khai báo Info.plist).
// ============================================================

enum FacebookOAuthError: LocalizedError {
    case badAppID
    case cancelled
    case noToken
    case denied(String)

    var errorDescription: String? {
        switch self {
        case .badAppID: return "App ID Facebook không hợp lệ (chỉ gồm chữ số)."
        case .cancelled: return "Đã huỷ đăng nhập."
        case .noToken: return "Không nhận được token từ Facebook."
        case .denied(let m): return "Facebook từ chối: \(m)"
        }
    }
}

@MainActor
final class FacebookOAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = FacebookOAuth()
    private var session: ASWebAuthenticationSession?

    /// Đăng nhập, trả về access token (EAA...).
    /// - appID: Facebook App ID (chuỗi số), lấy ở developers.facebook.com.
    func signIn(appID: String,
                scope: String = "public_profile,publish_video") async throws -> String {
        let id = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, id.allSatisfy({ $0.isNumber }) else { throw FacebookOAuthError.badAppID }

        let scheme = "fb\(id)"
        let redirect = "\(scheme)://authorize/"
        let state = GoogleOAuth.randomURLSafe(16)

        var comp = URLComponents(string: "https://www.facebook.com/v19.0/dialog/oauth")!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: id),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "display", value: "touch"),
        ]
        return try await authorize(url: comp.url!, scheme: scheme)
    }

    private func authorize(url: URL, scheme: String) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionError.errorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        cont.resume(throwing: FacebookOAuthError.cancelled)
                    } else {
                        cont.resume(throwing: error)
                    }
                    return
                }
                guard let callback else { cont.resume(throwing: FacebookOAuthError.noToken); return }
                // Token nằm trong fragment: fb123://authorize/#access_token=...&expires_in=...
                let frag = callback.fragment ?? ""
                let query = callback.query ?? ""
                if let tok = Self.value("access_token", frag) ?? Self.value("access_token", query) {
                    cont.resume(returning: tok)
                } else if let err = Self.value("error_description", query) ?? Self.value("error_description", frag)
                            ?? Self.value("error_message", query) ?? Self.value("error", query) {
                    cont.resume(throwing: FacebookOAuthError.denied(err.replacingOccurrences(of: "+", with: " ")))
                } else {
                    cont.resume(throwing: FacebookOAuthError.noToken)
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            self.session = s
            if !s.start() {
                cont.resume(throwing: FacebookOAuthError.cancelled)
            }
        }
    }

    private static func value(_ name: String, _ s: String) -> String? {
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0] == name {
                return kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.keniosKeyWindow ?? ASPresentationAnchor()
    }
}
