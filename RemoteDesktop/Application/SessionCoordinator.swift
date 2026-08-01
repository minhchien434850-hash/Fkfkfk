import Foundation

/// Manages multiple concurrent sessions: registration, resume, idle timeout,
/// recovery and migration. The UI can run several devices and switch between
/// them; idle sessions are reaped by `reap()`.
@MainActor
final class SessionCoordinator: ObservableObject {
    @Published private(set) var active: [RemoteSession] = []

    private var lastActivity: [UUID: Date] = [:]
    let timeout: TimeInterval

    init(timeout: TimeInterval = 600) { self.timeout = timeout }

    func register(_ session: RemoteSession) {
        active.removeAll { $0.device.id == session.device.id }
        active.append(session)
        lastActivity[session.id] = Date()
        AppLog.shared.info("Session registered: \(session.device.name)", category: "session")
    }

    /// Keep-alive: mark a session as recently used.
    func touch(_ id: UUID) { lastActivity[id] = Date() }

    func end(_ id: UUID) {
        active.removeAll { $0.id == id }
        lastActivity[id] = nil
    }

    /// Resume an existing session for a device if one is still registered.
    func resume(deviceId: String) -> RemoteSession? { active.first { $0.device.id == deviceId } }

    func expiredSessions(now: Date = Date()) -> [RemoteSession] {
        active.filter { now.timeIntervalSince(lastActivity[$0.id] ?? now) > timeout }
    }

    /// Remove idle sessions (Session Timeout / recovery).
    func reap() { expiredSessions().forEach { end($0.id) } }
}
