import Foundation
import LocalAuthentication

/// Face ID / Touch ID gate via `LocalAuthentication`.
final class BiometricAuthenticator: BiometricAuthenticatorProtocol {

    var isAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw RemoteError.biometricUnavailable
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if !success { throw RemoteError.unauthorized }
        } catch is RemoteError {
            throw RemoteError.unauthorized
        } catch {
            throw RemoteError.biometricUnavailable
        }
    }
}
