import Foundation

// MARK: - Authentication use cases (one responsibility each — SRP)

/// Signs a user in and persists the issued token.
struct LoginUseCase {
    private let auth: AuthServiceProtocol
    private let tokens: TokenStoreProtocol
    init(auth: AuthServiceProtocol, tokens: TokenStoreProtocol) {
        self.auth = auth; self.tokens = tokens
    }
    func callAsFunction(username: String, password: String) async throws -> User {
        let result = try await auth.login(username: username, password: password)
        try tokens.save(token: result.token)
        return result.user
    }
}

/// Refreshes the persisted access token.
struct RefreshTokenUseCase {
    private let auth: AuthServiceProtocol
    private let tokens: TokenStoreProtocol
    init(auth: AuthServiceProtocol, tokens: TokenStoreProtocol) {
        self.auth = auth; self.tokens = tokens
    }
    func callAsFunction() async throws {
        guard let current = tokens.load() else { throw RemoteError.unauthorized }
        let fresh = try await auth.refresh(token: current)
        try tokens.save(token: fresh)
    }
}

/// Clears the local session.
struct LogoutUseCase {
    private let tokens: TokenStoreProtocol
    init(tokens: TokenStoreProtocol) { self.tokens = tokens }
    func callAsFunction() { tokens.clear() }
}
