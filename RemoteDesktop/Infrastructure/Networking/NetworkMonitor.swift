import Foundation
import Network

/// Observes connectivity and the active interface using `Network.framework`.
/// Drives automatic Wi-Fi ↔ Cellular switching and reconnect decisions.
@MainActor
final class NetworkMonitor: ObservableObject {
    enum Interface: String { case wifi, cellular, wired, other, none }

    @Published private(set) var isConnected = true
    @Published private(set) var isExpensive = false
    @Published private(set) var interface: Interface = .other

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.kenios.remotedesktop.netmonitor")

    init() { start() }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.apply(path) }
        }
        monitor.start(queue: queue)
    }

    private func apply(_ path: NWPath) {
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        if path.usesInterfaceType(.wifi) { interface = .wifi }
        else if path.usesInterfaceType(.cellular) { interface = .cellular }
        else if path.usesInterfaceType(.wiredEthernet) { interface = .wired }
        else { interface = path.status == .satisfied ? .other : .none }
        AppLog.shared.info("Network: \(isConnected ? "up" : "down") via \(interface.rawValue)", category: "net")
    }

    func stop() { monitor.cancel() }
}
