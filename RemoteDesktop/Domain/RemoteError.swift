import Foundation

/// Unified domain error surfaced across all layers.
enum RemoteError: LocalizedError, Equatable {
    case network(String)
    case unauthorized
    case notFound
    case offline
    case decoding
    case biometricUnavailable
    case cancelled
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network(let m): return "Network error: \(m)"
        case .unauthorized:   return "Session expired. Please sign in again."
        case .notFound:       return "The requested resource was not found."
        case .offline:        return "The device is offline."
        case .decoding:       return "Could not read the server response."
        case .biometricUnavailable: return "Biometric authentication is unavailable."
        case .cancelled:      return "The operation was cancelled."
        case .unknown(let m): return m
        }
    }
}
