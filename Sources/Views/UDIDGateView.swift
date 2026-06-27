import SwiftUI

// ======================== Cổng lấy UDID khi cài app lần đầu ========================
// Lần cài đầu: bắt buộc lấy UDID qua web udid.tech → cài hồ sơ trong
// Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → rồi mới vào được app.
struct UDIDGateView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL
    @State private var opened = false
    @State private var confirm = false

    private let udidURL = URL(string: "https://udid.tech/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.heroGradient)
                        .frame(width: 104, height: 104)
                        .shadow(color: Theme.purple.opacity(0.5), radius: 22, y: 10)
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 52)).foregroundStyle(.white)
                }
                .padding(.top, 48)

                RainbowText(text: "KENIOS", size: 34)
                Text("Đăng ký thiết bị (UDID)")
                    .font(.headline)
                Text("Lần đầu cài app, bạn cần lấy UDID thiết bị để được cấp quyền sử dụng.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                // Các bước
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Bấm \"Lấy UDID\" — mở trang udid.tech, bấm lấy UDID và tải hồ sơ về.")
                    step(2, "Mở Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị.")
                    step(3, "Bấm vào hồ sơ vừa tải → Cài đặt (Install) để hoàn tất.")
                    step(4, "Quay lại đây, bấm \"Tôi đã lấy UDID & cài xong\" để vào app.")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // Nút lấy UDID
                Button {
                    opened = true
                    openURL(udidURL)
                } label: {
                    Label("Lấy UDID (mở udid.tech)", systemImage: "safari.fill")
                        .bold().frame(maxWidth: .infinity).padding()
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }.padding(.horizontal)

                // Nút mở Cài đặt iOS
                Button {
                    if let s = URL(string: UIApplication.openSettingsURLString) { openURL(s) }
                } label: {
                    Label("Mở Cài đặt iOS", systemImage: "gearshape.fill")
                        .frame(maxWidth: .infinity).padding()
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.4)))
                }.padding(.horizontal)

                // Xác nhận đã cài xong → vào app
                Toggle(isOn: $confirm) {
                    Text("Tôi đã lấy UDID và cài hồ sơ trong Cài đặt").font(.subheadline)
                }.tint(Theme.accent).padding(.horizontal)

                Button {
                    store.setUdidDone()
                } label: {
                    Text("Tôi đã lấy UDID & cài xong — Vào app")
                        .bold().frame(maxWidth: .infinity).padding()
                        .background(confirm ? Theme.purple : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!confirm)
                .padding(.horizontal)

                Text("UDID dùng để cấp quyền cài app cho riêng thiết bị của bạn. Sau khi cài hồ sơ, nhớ chọn \"Tin cậy\" nếu được hỏi.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal).padding(.bottom, 30)
            }
        }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.accent).clipShape(Circle())
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
