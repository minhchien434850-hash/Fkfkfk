import Foundation

/// Coordinates authentication and exposes an observable state to the UI.
/// Depends only on use cases + protocols (Dependency Inversion).
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var state: AuthState = .unknown
    @Published private(set) var currentUser: User?
    @Published var errorMessage: String?
    @Published var isBusy = false

    private let loginUseCase: LoginUseCase
    private let refreshUseCase: RefreshTokenUseCase
    private let logoutUseCase: LogoutUseCase
    private let biometrics: BiometricAuthenticatorProtocol
    private let tokens: TokenStoreProtocol
    private let settings: UserDefaultsStore

    init(loginUseCase: LoginUseCase,
         refreshUseCase: RefreshTokenUseCase,
         logoutUseCase: LogoutUseCase,
         biometrics: BiometricAuthenticatorProtocol,
         tokens: TokenStoreProtocol,
         settings: UserDefaultsStore) {
        self.loginUseCase = loginUseCase
        self.refreshUseCase = refreshUseCase
        self.logoutUseCase = logoutUseCase
        self.biometrics = biometrics
        self.tokens = tokens
        self.settings = settings
    }

    var biometricsAvailable: Bool { biometrics.isAvailable }
    var lastUsername: String { settings.lastUsername ?? "" }

    /// Called on launch: validate any stored token to skip the login screen.
    func restoreSession() async {
        guard state == .unknown else { return }
        guard tokens.load() != nil else { state = .signedOut; return }
        do { try await refreshUseCase(); state = .signedIn }
        catch { tokens.clear(); state = .signedOut }
    }

    func signIn(username: String, password: String) async {
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do {
            currentUser = try await loginUseCase(username: username, password: password)
            settings.lastUsername = username
            state = .signedIn
        } catch {
            errorMessage = (error as? RemoteError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Unlocks with Face ID / Touch ID when a token is already stored.
    func signInWithBiometrics() async {
        guard tokens.load() != nil else {
            errorMessage = "Sign in once with your password first."
            return
        }
        do {
            try await biometrics.authenticate(reason: "Unlock RemoteDesktop")
            try await refreshUseCase()
            state = .signedIn
        } catch {
            errorMessage = (error as? RemoteError)?.errorDescription ?? error.localizedDescription
        }
    }

    func signOut() {
        logoutUseCase()
        currentUser = nil
        state = .signedOut
    }
}
