import Foundation

/// View model for the login screen. Holds form state and delegates to
/// `AuthManager`; contains no networking or persistence itself (MVVM).
@MainActor
final class LoginViewModel: ObservableObject {
    @Published var username: String
    @Published var password: String = ""

    private let auth: AuthManager
    init(auth: AuthManager) {
        self.auth = auth
        self.username = auth.lastUsername
    }

    var isBusy: Bool { auth.isBusy }
    var errorMessage: String? { auth.errorMessage }
    var biometricsAvailable: Bool { auth.biometricsAvailable }
    var canSubmit: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty }

    func signIn() async {
        await auth.signIn(username: username.trimmingCharacters(in: .whitespaces), password: password)
    }
    func signInWithBiometrics() async { await auth.signInWithBiometrics() }
}
