import Foundation

/// Exponential-backoff retry policy with jitter and a max attempt cap.
/// Used by the connection supervisor and any transient network operation.
struct RetryPolicy {
    let maxAttempts: Int
    let baseDelay: Double
    let maxDelay: Double
    let jitter: Double

    init(maxAttempts: Int = 5, baseDelay: Double = 0.5, maxDelay: Double = 8, jitter: Double = 0.3) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.jitter = jitter
    }

    /// Delay (seconds) before the given 1-based attempt.
    func delay(forAttempt attempt: Int) -> Double {
        let exp = baseDelay * pow(2, Double(max(0, attempt - 1)))
        let capped = min(exp, maxDelay)
        let rand = Double.random(in: -jitter ... jitter) * capped
        return max(0, capped + rand)
    }

    /// Runs `operation` with retries; rethrows the last error if all attempts fail.
    func run<T>(_ operation: @Sendable () async throws -> T) async throws -> T {
        var lastError: Error = RemoteError.unknown("no attempt")
        for attempt in 1 ... maxAttempts {
            do { return try await operation() }
            catch is CancellationError { throw CancellationError() }
            catch {
                lastError = error
                if attempt < maxAttempts { await Task.sleep(seconds: delay(forAttempt: attempt)) }
            }
        }
        throw lastError
    }
}
