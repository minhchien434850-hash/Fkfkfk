import Foundation

// MARK: - Input domain model

/// Mouse buttons supported by the input engine.
enum MouseButton: String, Sendable { case left, right, double }

/// Media transport actions redirected to the remote host.
enum MediaAction: String, Sendable {
    case playpause, next, prev, mute, volup, voldown
}

/// System-level actions.
enum SystemAction: String, Sendable { case desktop, lock }

/// A normalized remote-input command produced by the Touch/Keyboard engines
/// and consumed by the `InputService`. `payload` is the wire representation
/// understood by the Desktop Agent / relay.
enum RemoteInput: Sendable {
    case move(dx: Int, dy: Int)
    case click(MouseButton)
    case scroll(dy: Int)
    case key(String)          // "enter" | "backspace" | "space" | "esc" …
    case text(String)
    case media(MediaAction)
    case system(SystemAction)

    /// JSON payload matching the relay `/pc/send` command schema.
    var payload: [String: Any] {
        switch self {
        case let .move(dx, dy):   return ["t": "move", "dx": dx, "dy": dy]
        case let .click(b):       return ["t": "click", "b": b.rawValue]
        case let .scroll(dy):     return ["t": "scroll", "dy": dy]
        case let .key(k):         return ["t": "key", "k": k]
        case let .text(s):        return ["t": "text", "s": s]
        case let .media(a):       return ["t": "media", "a": a.rawValue]
        case let .system(a):      return ["t": "sys", "a": a.rawValue]
        }
    }
}
