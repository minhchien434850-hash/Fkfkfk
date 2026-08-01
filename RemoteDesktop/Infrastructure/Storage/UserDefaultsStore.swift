import Foundation

/// Lightweight settings persistence (non-secure). Secure values go to Keychain.
final class UserDefaultsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var streamQuality: StreamQuality {
        get { StreamQuality(rawValue: defaults.string(forKey: "streamQuality") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "streamQuality") }
    }
    var biometricEnabled: Bool {
        get { defaults.bool(forKey: "biometricEnabled") }
        set { defaults.set(newValue, forKey: "biometricEnabled") }
    }
    var lastUsername: String? {
        get { defaults.string(forKey: "lastUsername") }
        set { defaults.set(newValue, forKey: "lastUsername") }
    }
}
