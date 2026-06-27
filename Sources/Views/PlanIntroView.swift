import SwiftUI

// ======================== Màn giới thiệu gói PRO / Free (hiện sau khi đăng nhập) ========================
struct PlanIntroView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showPay = false

    // Đầy đủ chức năng gói PRO
    private var proFeatures: [(String, String)] {
        [
            ("waveform", store.t("Giọng đọc AI ElevenLabs (TTS cao cấp, nhiều tông)", "ElevenLabs AI voice (premium TTS, many tones)")),
            ("bubble.left.and.bubble.right.fill", store.t("Nhắn tin: thủ công · tự động Web · tool nhóm", "Messaging: manual · auto Web · group tool")),
            ("scissors", store.t("Sửa video: cắt, lọc màu, chỉnh sáng, xuất MP4", "Video editor: trim, filters, brightness, export MP4")),
            ("dot.radiowaves.left.and.right", store.t("Live Tools / Stream key đa nền tảng", "Live Tools / multi-platform stream key")),
            ("arrow.down.circle.fill", store.t("Tải video chất lượng cao tới 4K", "Download videos up to 4K")),
            ("square.grid.2x2.fill", store.t("Mở khoá toàn bộ công cụ sáng tạo", "Unlock all creator tools")),
            ("bolt.fill", store.t("Ưu tiên xử lý & hỗ trợ nhanh", "Priority processing & support")),
        ]
    }
    // Đầy đủ chức năng gói Free
    private var freeFeatures: [(String, String)] {
        [
            ("network", store.t("Mạng xã hội · đăng & xem Video/Reels", "Social · post & watch Video/Reels")),
            ("bag.fill", store.t("Cửa hàng: mua sản phẩm số / key / acc", "Store: buy digital products / keys / accounts")),
            ("person.2.fill", store.t("Bạn bè & nhắn tin trực tiếp (DM)", "Friends & direct messages (DM)")),
            ("speaker.wave.2.fill", store.t("Đọc TTS giọng hệ thống (iOS · Google)", "TTS with system voices (iOS · Google)")),
            ("square.grid.2x2", store.t("Trò chơi · Thư viện · Giải trí · GitHub", "Games · Library · Entertainment · GitHub")),
            ("wand.and.stars", store.t("Chuyển đổi ảnh/video → link GIF/PNG", "Convert image/video → GIF/PNG link")),
            ("hammer.fill", store.t("Bộ công cụ tiện ích cơ bản", "Basic utility toolkit")),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        RainbowText(text: "KENIOS", size: 34)
                        Text(store.t("Chọn gói phù hợp với bạn", "Choose the plan that fits you"))
                            .font(.headline)
                        Text(store.t("Bạn đang dùng gói:", "Your current plan:") + " " + (store.isPro ? "PRO" : "Free"))
                            .font(.subheadline)
                            .foregroundStyle(store.isPro ? Theme.gold : .secondary)
                    }
                    .padding(.top, 8)
                    .multilineTextAlignment(.center)

                    // iPad: 2 cột cạnh nhau · iPhone: xếp dọc — luôn thấy được cả 2 gói
                    if hSize == .regular {
                        HStack(alignment: .top, spacing: 16) {
                            proCard.frame(maxWidth: .infinity)
                            freeCard.frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 16) {
                            proCard
                            freeCard
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { dismiss() }
                }
            }
            .sheet(isPresented: $showPay) { PaymentView() }
        }
    }

    // MARK: - Thẻ gói PRO
    private var proCard: some View {
        planCard(
            title: store.t("Gói PRO", "PRO plan"),
            subtitle: store.t("Mở khoá đầy đủ tính năng nâng cao", "Unlock all advanced features"),
            icon: "crown.fill",
            tint: Theme.gold,
            features: proFeatures,
            highlight: true
        ) {
            if !store.isPro {
                Button { showPay = true } label: {
                    Label(store.t("Nâng cấp PRO", "Upgrade to PRO"), systemImage: "crown")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.buttonGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                Label(store.t("Bạn đã là PRO 🎉", "You're PRO 🎉"), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold()).foregroundStyle(.green)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Thẻ gói Free
    private var freeCard: some View {
        planCard(
            title: store.t("Gói Free", "Free plan"),
            subtitle: store.t("Dùng miễn phí các tính năng cơ bản", "Use the basics for free"),
            icon: "gift.fill",
            tint: Theme.accent,
            features: freeFeatures,
            highlight: false
        ) {
            Button { dismiss() } label: {
                Text(store.t("Tiếp tục dùng Free", "Continue with Free"))
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Khung thẻ dùng chung
    private func planCard<Footer: View>(title: String, subtitle: String, icon: String,
                                        tint: Color, features: [(String, String)],
                                        highlight: Bool,
                                        @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.bold())
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(features, id: \.1) { f in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: highlight ? "checkmark.seal.fill" : "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(highlight ? tint : .green)
                            .padding(.top, 1)
                        Text(f.1)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            footer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(highlight ? tint.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }
}
