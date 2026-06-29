import Foundation
import NetworkExtension
import Combine

/// Quản lý toàn bộ vòng đời VPN từ phía Main App.
/// Sử dụng NETunnelProviderManager để tạo/lưu cấu hình VPN
/// và điều khiển bật/tắt tunnel.
final class VPNManager: ObservableObject {

    static let shared = VPNManager()

    // MARK: - Published State

    @Published var status: NEVPNStatus = .disconnected
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var connectedDate: Date?

    // MARK: - WireGuard Config

    @Published var privateKey: String = ""
    @Published var publicKey: String = ""
    @Published var endpoint: String = ""
    @Published var dns: String = "1.1.1.1,8.8.8.8"
    @Published var address: String = "10.0.0.2"
    @Published var subnet: String = "32"
    @Published var mtu: Int = 1360

    // Bundle ID của Packet Tunnel Extension — PHẢI khớp với target trong Xcode
    private let tunnelBundleId = "com.kenios.codebox.PacketTunnel"

    private var manager: NETunnelProviderManager?
    private var statusObserver: Any?

    // MARK: - Init

    private init() {
        loadFromKeychain()
        loadExistingManager()
    }

    deinit {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Load Existing VPN Configuration

    /// Tìm cấu hình VPN đã lưu trước đó trong Settings → VPN.
    /// Nếu tìm thấy, đồng bộ trạng thái ngay.
    func loadExistingManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                if let error {
                    self?.errorMessage = error.localizedDescription
                    return
                }
                // Tìm manager khớp với bundle ID của extension
                let existing = managers?.first {
                    ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                        .providerBundleIdentifier == self?.tunnelBundleId
                }
                self?.manager = existing
                self?.status = existing?.connection.status ?? .disconnected
                self?.observeStatus()
            }
        }
    }

    // MARK: - Save VPN Preferences (đẩy vào Cài Đặt → VPN)

    /// Tạo hoặc cập nhật cấu hình VPN trong hệ thống.
    /// Sau khi gọi hàm này, mục VPN sẽ xuất hiện trong Settings → VPN.
    func loadAndSaveVPNPreferences() async throws {
        await MainActor.run { isLoading = true; errorMessage = nil }

        // Validate đầu vào
        guard !privateKey.isEmpty, !publicKey.isEmpty, !endpoint.isEmpty else {
            await MainActor.run {
                errorMessage = "Vui lòng điền đầy đủ Private Key, Public Key và Endpoint."
                isLoading = false
            }
            return
        }

        do {
            // Tải danh sách manager hiện có
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            let mgr = managers.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == tunnelBundleId
            } ?? NETunnelProviderManager()

            // Tạo protocol configuration
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = tunnelBundleId
            proto.serverAddress = endpoint

            // Truyền cấu hình WireGuard sang Extension qua providerConfiguration
            proto.providerConfiguration = [
                "privateKey": privateKey,
                "publicKey": publicKey,
                "endpoint": endpoint,
                "dns": dns,
                "address": address,
                "subnet": subnet,
                "mtu": mtu
            ] as [String: Any]

            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "KENIOS VPN"
            mgr.isEnabled = true

            // Lưu cấu hình vào hệ thống (xuất hiện trong Settings → VPN)
            try await mgr.saveToPreferences()
            // Phải load lại sau khi save để manager sẵn sàng start
            try await mgr.loadFromPreferences()

            saveToKeychain()

            await MainActor.run {
                self.manager = mgr
                self.status = mgr.connection.status
                self.isLoading = false
                self.observeStatus()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    // MARK: - Toggle VPN

    /// Bật hoặc tắt VPN. Nếu chưa có cấu hình, tự động lưu trước.
    func toggleVPN() async {
        guard let mgr = manager else {
            do {
                try await loadAndSaveVPNPreferences()
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
                return
            }
            // Sau khi lưu xong, thử toggle lại
            await toggleVPN()
            return
        }

        let currentStatus = mgr.connection.status

        if currentStatus == .connected || currentStatus == .connecting {
            mgr.connection.stopVPNTunnel()
        } else {
            await MainActor.run { isLoading = true; errorMessage = nil }
            do {
                try mgr.connection.startVPNTunnel()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Observe NEVPNStatusDidChange

    private func observeStatus() {
        if let obs = statusObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        guard let connection = manager?.connection else { return }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let newStatus = connection.status
            self.status = newStatus
            self.isLoading = false

            switch newStatus {
            case .connected:
                self.connectedDate = Date()
            case .disconnected, .invalid:
                self.connectedDate = nil
            default:
                break
            }
        }
    }

    // MARK: - Remove VPN Configuration

    func removeVPN() async {
        guard let mgr = manager else { return }
        do {
            try await mgr.removeFromPreferences()
            await MainActor.run {
                self.manager = nil
                self.status = .disconnected
                self.connectedDate = nil
            }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Persistence (UserDefaults — keys không phải secret nên OK ở đây)

    private let udKey = "kenios_vpn_config"

    private func saveToKeychain() {
        let dict: [String: String] = [
            "privateKey": privateKey,
            "publicKey": publicKey,
            "endpoint": endpoint,
            "dns": dns,
            "address": address,
            "subnet": subnet,
            "mtu": "\(mtu)"
        ]
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: udKey)
        }
    }

    private func loadFromKeychain() {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        privateKey = dict["privateKey"] ?? ""
        publicKey  = dict["publicKey"] ?? ""
        endpoint   = dict["endpoint"] ?? ""
        dns        = dict["dns"] ?? "1.1.1.1,8.8.8.8"
        address    = dict["address"] ?? "10.0.0.2"
        subnet     = dict["subnet"] ?? "32"
        mtu        = Int(dict["mtu"] ?? "1360") ?? 1360
    }

    // MARK: - Status Helpers

    var statusText: String {
        switch status {
        case .connected:     return "Đã kết nối"
        case .connecting:    return "Đang kết nối..."
        case .disconnecting: return "Đang ngắt..."
        case .disconnected:  return "Đã ngắt kết nối"
        case .reasserting:   return "Đang khôi phục..."
        case .invalid:       return "Cấu hình không hợp lệ"
        @unknown default:    return "Không xác định"
        }
    }

    var statusColor: String {
        switch status {
        case .connected:     return "green"
        case .connecting, .reasserting, .disconnecting: return "orange"
        default:             return "gray"
        }
    }

    var isConnected: Bool { status == .connected }

    var uptimeText: String? {
        guard let date = connectedDate else { return nil }
        let elapsed = Int(Date().timeIntervalSince(date))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
