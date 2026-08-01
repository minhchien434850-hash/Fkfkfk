import Foundation

/// View model for the settings screen (quality, security, diagnostics).
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var quality: StreamQuality { didSet { settings.streamQuality = quality } }
    @Published var biometricEnabled: Bool { didSet { settings.biometricEnabled = biometricEnabled } }

    private let settings: UserDefaultsStore
    private let auth: AuthManager

    init(settings: UserDefaultsStore, auth: AuthManager) {
        self.settings = settings
        self.auth = auth
        self.quality = settings.streamQuality
        self.biometricEnabled = settings.biometricEnabled
    }

    var username: String { auth.currentUser?.displayName ?? settings.lastUsername ?? "—" }
    var serverURL: String { AppConfig.serverBaseURL.absoluteString }
    var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    func signOut() { auth.signOut() }
}
