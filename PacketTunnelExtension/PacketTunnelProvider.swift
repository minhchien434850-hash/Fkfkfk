import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.kenios.codebox.PacketTunnel", category: "tunnel")

    // MARK: - Start Tunnel

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        os_log("startTunnel called", log: log, type: .info)

        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let conf = proto.providerConfiguration else {
            completionHandler(PacketTunnelError.missingConfiguration)
            return
        }

        guard let privateKey = conf["privateKey"] as? String,
              let publicKey  = conf["publicKey"]  as? String,
              let endpoint   = conf["endpoint"]   as? String,
              !privateKey.isEmpty, !publicKey.isEmpty, !endpoint.isEmpty else {
            completionHandler(PacketTunnelError.invalidKeys)
            return
        }

        let dns      = (conf["dns"] as? String) ?? "1.1.1.1,8.8.8.8"
        let mtuValue = (conf["mtu"] as? Int) ?? 1360
        let address  = (conf["address"] as? String) ?? "10.0.0.2"
        let subnet   = (conf["subnet"] as? String) ?? "32"

        let settings = buildTunnelSettings(
            address: address,
            subnet: subnet,
            dns: dns,
            mtu: mtuValue
        )

        os_log("Applying tunnel settings: addr=%{public}@ mtu=%d dns=%{public}@",
               log: log, type: .info, address, mtuValue, dns)

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error {
                os_log("setTunnelNetworkSettings failed: %{public}@",
                       log: self?.log ?? .default, type: .error, error.localizedDescription)
                completionHandler(error)
                return
            }
            os_log("Tunnel settings applied successfully", log: self?.log ?? .default, type: .info)
            self?.readPackets()
            completionHandler(nil)
        }
    }

    // MARK: - Stop Tunnel

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        os_log("stopTunnel called, reason=%d", log: log, type: .info, reason.rawValue)
        completionHandler()
    }

    // MARK: - Build NEPacketTunnelNetworkSettings

    private func buildTunnelSettings(address: String, subnet: String, dns: String, mtu: Int) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "0.0.0.0")

        // IPv4 — gắn địa chỉ tunnel và route toàn bộ lưu lượng qua đường hầm
        let ipv4 = NEIPv4Settings(addresses: [address], subnetMasks: [subnetMaskFrom(prefix: subnet)])
        // Route 0.0.0.0/0 = ép MỌI traffic qua VPN (full tunnel)
        ipv4.includedRoutes = [NEIPv4Route.default()]
        ipv4.excludedRoutes = []
        settings.ipv4Settings = ipv4

        // DNS
        let dnsServers = dns
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        settings.dnsSettings = NEDNSSettings(servers: dnsServers.isEmpty ? ["1.1.1.1", "8.8.8.8"] : dnsServers)

        // MTU tối ưu cho gaming (1280–1420)
        let clampedMTU = max(1280, min(1420, mtu))
        settings.mtu = NSNumber(value: clampedMTU)

        return settings
    }

    // MARK: - Packet I/O

    private func readPackets() {
        packetFlow.readPackets { [weak self] packets, protocols in
            // Trong triển khai đầy đủ WireGuard, đây là nơi mã hoá packet rồi gửi qua UDP socket.
            // Hiện tại đọc liên tục để giữ tunnel sống.
            self?.readPackets()
        }
    }

    // MARK: - Helpers

    private func subnetMaskFrom(prefix: String) -> String {
        let bits = Int(prefix) ?? 32
        guard bits >= 0 && bits <= 32 else { return "255.255.255.255" }
        let mask = bits == 0 ? 0 : UInt32.max << (32 - bits)
        return [
            (mask >> 24) & 0xFF,
            (mask >> 16) & 0xFF,
            (mask >> 8)  & 0xFF,
            mask         & 0xFF
        ].map { String($0) }.joined(separator: ".")
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        if let str = String(data: messageData, encoding: .utf8) {
            os_log("App message: %{public}@", log: log, type: .info, str)
        }
        completionHandler?(nil)
    }
}

// MARK: - Errors

enum PacketTunnelError: LocalizedError {
    case missingConfiguration
    case invalidKeys

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "Missing tunnel provider configuration"
        case .invalidKeys:          return "Invalid or empty WireGuard keys"
        }
    }
}
