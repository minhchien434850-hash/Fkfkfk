import Foundation
import UIKit

/// Zero-Trust device posture checks performed before allowing remote control.
struct DeviceValidator {

    var deviceIdentifier: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    /// Heuristic jailbreak detection (files + sandbox escape write test).
    var isJailbroken: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let suspiciousPaths = ["/Applications/Cydia.app", "/usr/sbin/sshd",
                               "/bin/bash", "/etc/apt", "/private/var/lib/apt/"]
        if suspiciousPaths.contains(where: { FileManager.default.fileExists(atPath: $0) }) { return true }
        let probe = "/private/.rd_jailbreak_probe"
        do {
            try "x".write(toFile: probe, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probe)
            return true   // writing outside the sandbox succeeded → compromised
        } catch {
            return false
        }
        #endif
    }

    /// Throws when the device is not trusted (Zero-Trust gate).
    func validate() throws {
        if isJailbroken {
            AppLog.shared.warning("Blocked control from a compromised device", category: "security")
            throw RemoteError.unknown("This device failed the security check and cannot start a session.")
        }
    }
}
