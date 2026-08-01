import Foundation

/// Thin async HTTP client over `URLSession`.
/// - Adds the bearer token (provided lazily so it stays decoupled from storage).
/// - Normalizes transport/status failures into `RemoteError`.
final class APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: () -> String?

    init(baseURL: URL,
         tokenProvider: @escaping () -> String?,
         session: URLSession = APIClient.makeSession()) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    /// Builds a session with sane timeouts. A pinning delegate can be attached.
    static func makeSession(pinning: TLSPinningDelegate? = nil) -> URLSession {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = AppConfig.requestTimeout
        cfg.timeoutIntervalForResource = AppConfig.resourceTimeout
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg, delegate: pinning, delegateQueue: nil)
    }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, auth: Bool = true) async throws -> T {
        try decode(try await data(for: request(path, method: "GET", auth: auth)))
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> T {
        var req = request(path, method: "POST", auth: auth)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return try decode(try await data(for: req))
    }

    func delete(_ path: String, auth: Bool = true) async throws {
        _ = try await data(for: request(path, method: "DELETE", auth: auth))
    }

    /// Raw GET returning bytes (used by the streaming layer).
    func raw(_ path: String, auth: Bool = true) async throws -> Data {
        try await data(for: request(path, method: "GET", auth: auth))
    }

    // MARK: Internals

    private func request(_ path: String, method: String, auth: Bool) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if auth, let token = tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func data(for req: URLRequest) async throws -> Data {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw RemoteError.network(error.localizedDescription) }
        guard let http = resp as? HTTPURLResponse else { throw RemoteError.decoding }
        switch http.statusCode {
        case 200..<300: return data
        case 401:       throw RemoteError.unauthorized
        case 404:       throw RemoteError.notFound
        default:
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw RemoteError.network(detail ?? "HTTP \(http.statusCode)")
        }
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        do { return try dec.decode(T.self, from: data) }
        catch { throw RemoteError.decoding }
    }
}
