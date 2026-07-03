import Foundation

/// `AuthServiceProtocol` implementation backed by the KENIOS relay `/auth/login`.
/// Tokens are long-lived JWTs; `refresh` re-validates by round-tripping the
/// token and returns it (the relay has no separate refresh endpoint).
final class AuthService: AuthServiceProtocol {
    private let api: APIClient
    init(api: APIClient) { self.api = api }

    func login(username: String, password: String) async throws -> (user: User, token: String) {
        let dto: LoginResponseDTO = try await api.post(
            Endpoints.login, body: ["username": username, "password": password], auth: false)
        let name = dto.user?.username ?? username
        let id = dto.user?.id.map(String.init) ?? name
        return (User(id: id, username: name, displayName: name), dto.token)
    }

    func refresh(token: String) async throws -> String {
        // Validate the token with a lightweight authorized call; keep it if valid.
        let _: [DeviceDTO] = try await api.get(Endpoints.devices, auth: true)
        return token
    }
}
