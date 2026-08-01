import Foundation

/// Keeps a logical connection alive: periodic heartbeat, keep-alive, and
/// automatic reconnect with an exponential-backoff `RetryPolicy`. Reusable by
/// any session; publishes an observable link state for the HUD.
@MainActor
final class ConnectionSupervisor: ObservableObject {
    enum State: Equatable { case connected, reconnecting, offline }

    @Published private(set) var state: State = .connected

    private let heartbeatInterval: TimeInterval
    private let policy: RetryPolicy
    private var loop: Task<Void, Never>?
    private var healthCheck: (@Sendable () async -> Bool)?

    init(heartbeatInterval: TimeInterval = 5, policy: RetryPolicy = RetryPolicy()) {
        self.heartbeatInterval = heartbeatInterval
        self.policy = policy
    }

    /// Start supervising. `healthCheck` returns true while the link is healthy.
    func start(healthCheck: @escaping @Sendable () async -> Bool) {
        self.healthCheck = healthCheck
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.beat()
                await Task.sleep(seconds: self.heartbeatInterval)
            }
        }
    }

    func stop() { loop?.cancel(); loop = nil; state = .connected }

    private func beat() async {
        guard let healthCheck else { return }
        if await healthCheck() { state = .connected; return }
        // Unhealthy → attempt reconnect with backoff.
        state = .reconnecting
        for attempt in 1 ... policy.maxAttempts {
            await Task.sleep(seconds: policy.delay(forAttempt: attempt))
            if await healthCheck() { state = .connected; return }
        }
        state = .offline
    }
}
