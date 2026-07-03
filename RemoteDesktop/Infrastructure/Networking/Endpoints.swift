import Foundation

/// Centralized relay endpoint paths (single source of truth).
enum Endpoints {
    static let login = "auth/login"
    static let devices = "pc/mine"
    static func screen(_ id: String) -> String { "pc/screen/\(id)" }
    static let sendInput = "pc/send"
    static func device(_ id: String) -> String { "pc/\(id)" }
}
