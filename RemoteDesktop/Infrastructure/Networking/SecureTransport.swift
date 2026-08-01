import Foundation
import Network

/// Low-level secure transport factory using `Network.framework`.
/// - TLS 1.3 over TCP (primary, fully supported).
/// - QUIC parameters for a low-latency Desktop Agent path (iOS 15+).
/// The `NWConnection` wrapper exposes async connect/send and a receive stream.
enum SecureTransport {

    /// TLS 1.3 parameters (minimum + maximum pinned to 1.3).
    static func tls13Parameters() -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        return NWParameters(tls: tls)
    }

    /// QUIC parameters (HTTP/3-style ALPN). QUIC mandates TLS 1.3 by spec.
    /// Requires an agent QUIC listener.
    static func quicParameters(alpn: [String] = ["kenios-rd"]) -> NWParameters {
        let quic = NWProtocolQUIC.Options(alpn: alpn)
        return NWParameters(quic: quic)
    }
}

/// Thin async wrapper over `NWConnection`.
final class SecureConnection {
    private let connection: NWConnection

    init(host: String, port: UInt16, parameters: NWParameters) {
        connection = NWConnection(host: NWEndpoint.Host(host),
                                  port: NWEndpoint.Port(rawValue: port) ?? .https,
                                  using: parameters)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: cont.resume()
                case .failed(let error): cont.resume(throwing: error)
                case .cancelled: cont.resume(throwing: RemoteError.cancelled)
                default: break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    func receive() -> AsyncStream<Data> {
        AsyncStream { continuation in
            func read() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let data, !data.isEmpty { continuation.yield(data) }
                    if isComplete || error != nil { continuation.finish() } else { read() }
                }
            }
            read()
            continuation.onTermination = { [connection] _ in connection.cancel() }
        }
    }

    func close() { connection.cancel() }
}
