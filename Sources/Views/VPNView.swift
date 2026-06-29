import SwiftUI
import NetworkExtension

struct VPNView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var vpn = VPNManager.shared
    @State private var showConfig = false
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    statusSection
                    connectButton
                    if vpn.isConnected, let uptime = vpn.uptimeText {
                        uptimeView(uptime)
                    }
                    if let err = vpn.errorMessage {
                        errorBanner(err)
                    }
                    configSummary
                }
                .padding()
            }
            .background(Theme.bgNavy.ignoresSafeArea())
            .navigationTitle(store.t("VPN", "VPN"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showConfig = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .sheet(isPresented: $showConfig) {
                VPNConfigSheet(vpn: vpn)
                    .environmentObject(store)
            }
            .onReceive(timer) { _ in
                if vpn.isConnected {
                    vpn.objectWillChange.send()
                }
            }
        }
    }

    // MARK: - Status Circle

    private var statusSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(statusGradient.opacity(0.15))
                    .frame(width: 180, height: 180)

                Circle()
                    .fill(statusGradient.opacity(0.3))
                    .frame(width: 140, height: 140)

                Circle()
                    .fill(statusGradient)
                    .frame(width: 100, height: 100)
                    .overlay {
                        Image(systemName: vpn.isConnected ? "lock.shield.fill" : "shield.slash")
                            .font(.system(size: 36))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: statusAccent.opacity(0.5), radius: 20)
            }
            .padding(.top, 20)

            Text(vpn.statusText)
                .font(.title2.bold())
                .foregroundStyle(.white)

            if vpn.isConnected {
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text(store.t("Bảo mật toàn bộ lưu lượng mạng", "All network traffic secured"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            Task { await vpn.toggleVPN() }
        } label: {
            HStack(spacing: 12) {
                if vpn.isLoading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: vpn.isConnected ? "stop.fill" : "play.fill")
                }
                Text(buttonText)
                    .font(.headline.bold())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(buttonGradient)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: statusAccent.opacity(0.4), radius: 10, y: 4)
        }
        .disabled(vpn.isLoading)
        .padding(.horizontal)
    }

    // MARK: - Uptime

    private func uptimeView(_ text: String) -> some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(Theme.gold)
            Text(store.t("Thời gian kết nối:", "Connected time:"))
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(text)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Error Banner

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(msg)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button {
                vpn.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    // MARK: - Config Summary

    private var configSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.t("Thông tin kết nối", "Connection info"))
                .font(.subheadline.bold())
                .foregroundStyle(.white)

            if vpn.endpoint.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.orange)
                    Text(store.t("Chưa cấu hình. Bấm ⚙ để nhập thông tin server.",
                                 "Not configured. Tap ⚙ to enter server info."))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                configRow(icon: "server.rack", label: "Endpoint", value: vpn.endpoint)
                configRow(icon: "globe", label: "DNS", value: vpn.dns)
                configRow(icon: "network", label: store.t("Địa chỉ", "Address"), value: "\(vpn.address)/\(vpn.subnet)")
                configRow(icon: "arrow.up.arrow.down", label: "MTU", value: "\(vpn.mtu)")
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func configRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Theme.gold)
                .frame(width: 20)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    // MARK: - Colors

    private var statusAccent: Color {
        switch vpn.status {
        case .connected: return .green
        case .connecting, .reasserting, .disconnecting: return .orange
        default: return .gray
        }
    }

    private var statusGradient: LinearGradient {
        switch vpn.status {
        case .connected:
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .top, endPoint: .bottom)
        case .connecting, .reasserting, .disconnecting:
            return LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom)
        default:
            return LinearGradient(colors: [.gray, .gray.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
    }

    private var buttonGradient: LinearGradient {
        vpn.isConnected
            ? LinearGradient(colors: [.red.opacity(0.9), .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
    }

    private var buttonText: String {
        switch vpn.status {
        case .connected:     return store.t("Ngắt kết nối", "Disconnect")
        case .connecting:    return store.t("Đang kết nối...", "Connecting...")
        case .disconnecting: return store.t("Đang ngắt...", "Disconnecting...")
        default:             return store.t("Kết nối VPN", "Connect VPN")
        }
    }
}

// MARK: - VPN Configuration Sheet

struct VPNConfigSheet: View {
    @ObservedObject var vpn: VPNManager
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("WireGuard Keys", "WireGuard Keys")) {
                    SecureField("Private Key", text: $vpn.privateKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Server Public Key", text: $vpn.publicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Server") {
                    TextField(store.t("Endpoint (IP:Port)", "Endpoint (IP:Port)"), text: $vpn.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                    TextField("DNS (1.1.1.1,8.8.8.8)", text: $vpn.dns)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                }

                Section(store.t("Mạng", "Network")) {
                    TextField(store.t("Địa chỉ tunnel (10.0.0.2)", "Tunnel address (10.0.0.2)"), text: $vpn.address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                    TextField(store.t("Subnet prefix (32)", "Subnet prefix (32)"), text: $vpn.subnet)
                        .keyboardType(.numberPad)
                    Stepper("MTU: \(vpn.mtu)", value: $vpn.mtu, in: 1280...1420, step: 20)
                    Text(store.t("MTU 1280–1420 tối ưu cho gaming. Giá trị thấp hơn ổn định hơn, cao hơn nhanh hơn.",
                                 "MTU 1280–1420 optimized for gaming. Lower = more stable, higher = faster."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            try? await vpn.loadAndSaveVPNPreferences()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if vpn.isLoading { ProgressView().padding(.trailing, 4) }
                            Text(store.t("Lưu cấu hình", "Save configuration"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(vpn.privateKey.isEmpty || vpn.publicKey.isEmpty || vpn.endpoint.isEmpty)
                }

                Section {
                    Button(store.t("Xoá cấu hình VPN", "Remove VPN configuration"), role: .destructive) {
                        Task {
                            await vpn.removeVPN()
                            dismiss()
                        }
                    }
                }

                Section {
                    Text(store.t(
                        "Cấu hình WireGuard sẽ được lưu vào Cài đặt → VPN trên iPhone. Bạn có thể bật/tắt VPN từ app hoặc từ Cài đặt hệ thống.",
                        "WireGuard config will be saved to Settings → VPN on iPhone. You can toggle VPN from the app or system Settings."
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("Cấu hình VPN", "VPN Configuration"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { dismiss() }
                }
            }
        }
    }
}
