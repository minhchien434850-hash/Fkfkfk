import SwiftUI

// ======================== Pháp lý: Điều khoản & Chính sách bảo mật ========================
struct LegalView: View {
    @EnvironmentObject var store: AppStore

    // Biểu tượng cho từng mục (khớp thứ tự 1..9 của nội dung) — cho bắt mắt, dễ đọc.
    static let termsIcons = [
        "checkmark.seal.fill", "person.crop.circle.fill", "hand.raised.fill",
        "cart.fill", "square.and.pencil", "crown.fill",
        "exclamationmark.shield.fill", "arrow.triangle.2.circlepath", "envelope.fill"
    ]
    static let privacyIcons = [
        "tray.full.fill", "gearshape.fill", "externaldrive.fill",
        "arrow.left.arrow.right", "iphone.gen3", "person.badge.key.fill",
        "figure.child", "arrow.triangle.2.circlepath", "envelope.fill"
    ]

    // Tài liệu dùng chung (gọi được cả từ màn đăng nhập).
    static func termsDoc(_ store: AppStore) -> LegalDocView {
        LegalDocView(title: store.t("Điều khoản sử dụng", "Terms of Use"),
                     headerIcon: "doc.text.fill", accent: .blue,
                     content: termsBody(store), icons: termsIcons)
    }
    static func privacyDoc(_ store: AppStore) -> LegalDocView {
        LegalDocView(title: store.t("Chính sách bảo mật", "Privacy Policy"),
                     headerIcon: "lock.shield.fill", accent: Theme.accent,
                     content: privacyBody(store), icons: privacyIcons)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Hero
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Theme.accent.gradient).frame(width: 68, height: 68)
                            .shadow(color: Theme.accent.opacity(0.4), radius: 10, y: 4)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                    }
                    Text(store.t("Pháp lý & Minh bạch", "Legal & Transparency"))
                        .font(.title3.bold())
                    Text(store.t("Cam kết của KENIOS về quyền lợi và dữ liệu của bạn",
                                 "KENIOS' commitment to your rights and data"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                // 2 thẻ điều hướng
                NavigationLink {
                    LegalView.termsDoc(store)
                } label: {
                    legalCard(icon: "doc.text.fill", tint: .blue,
                              title: store.t("Điều khoản sử dụng", "Terms of Use"),
                              subtitle: store.t("Quy định khi dùng KENIOS: tài khoản, mua hàng, nội dung.",
                                                "Rules for using KENIOS: account, purchases, content."))
                }.buttonStyle(.plain)

                NavigationLink {
                    LegalView.privacyDoc(store)
                } label: {
                    legalCard(icon: "lock.shield.fill", tint: Theme.accent,
                              title: store.t("Chính sách bảo mật", "Privacy Policy"),
                              subtitle: store.t("Cách chúng tôi thu thập, dùng và bảo vệ dữ liệu của bạn.",
                                                "How we collect, use and protect your data."))
                }.buttonStyle(.plain)

                // Ghi chú đồng ý
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent).font(.caption)
                    Text(store.t("Bằng việc dùng KENIOS, bạn đồng ý với Điều khoản & Chính sách bảo mật.",
                                 "By using KENIOS, you agree to the Terms & Privacy Policy."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.08)))
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(store.t("Pháp lý", "Legal"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // Thẻ điều hướng đẹp: icon gradient + tiêu đề + mô tả + chevron.
    private func legalCard(icon: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(tint.gradient).frame(width: 48, height: 48)
                    .shadow(color: tint.opacity(0.35), radius: 6, y: 3)
                Image(systemName: icon).font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    static func termsBody(_ store: AppStore) -> String {
        store.t(
        """
        Cập nhật lần cuối: 2026

        1. CHẤP NHẬN ĐIỀU KHOẢN
        Khi tạo tài khoản hoặc sử dụng ứng dụng KENIOS, bạn đồng ý tuân theo các điều khoản này. Nếu không đồng ý, vui lòng ngừng sử dụng.

        2. TÀI KHOẢN
        Bạn chịu trách nhiệm bảo mật tài khoản và mật khẩu của mình, cũng như mọi hoạt động phát sinh từ tài khoản. Không chia sẻ tài khoản cho người khác.

        3. SỬ DỤNG HỢP LỆ
        Bạn không được dùng ứng dụng để: vi phạm pháp luật; phát tán nội dung độc hại, lừa đảo, spam; xâm phạm quyền riêng tư hay tài sản của người khác; can thiệp/làm gián đoạn hệ thống.

        4. MUA HÀNG & VÍ
        Sản phẩm số (key/tài khoản/bản tải) được giao tự động sau khi thanh toán thành công. Số dư ví dùng để mua hàng trong ứng dụng. Vui lòng kiểm tra kỹ trước khi mua; chính sách đổi/hoàn theo thông báo của cửa hàng.

        5. NỘI DUNG NGƯỜI DÙNG
        Bạn giữ quyền với nội dung mình đăng (video, bài viết) nhưng cấp cho KENIOS quyền lưu trữ và hiển thị nội dung đó trong ứng dụng. Bạn chịu trách nhiệm về nội dung mình đăng tải.

        6. GÓI PRO
        Một số tính năng nâng cao yêu cầu gói PRO. Quyền lợi gói có thể thay đổi; chúng tôi sẽ thông báo khi có cập nhật quan trọng.

        7. GIỚI HẠN TRÁCH NHIỆM
        Ứng dụng cung cấp "nguyên trạng". Trong phạm vi pháp luật cho phép, KENIOS không chịu trách nhiệm cho thiệt hại gián tiếp phát sinh từ việc sử dụng.

        8. THAY ĐỔI
        Chúng tôi có thể cập nhật điều khoản theo thời gian. Việc tiếp tục sử dụng đồng nghĩa bạn chấp nhận điều khoản mới.

        9. LIÊN HỆ
        Mọi thắc mắc xin liên hệ admin qua mục Liên hệ trong cửa hàng.
        """,
        """
        Last updated: 2026

        1. ACCEPTANCE
        By creating an account or using the KENIOS app, you agree to these terms. If you do not agree, please stop using the app.

        2. ACCOUNT
        You are responsible for keeping your account and password secure and for all activity under your account. Do not share your account.

        3. ACCEPTABLE USE
        You may not use the app to: break the law; distribute harmful, fraudulent or spam content; violate others' privacy or property; or disrupt the system.

        4. PURCHASES & WALLET
        Digital products (keys/accounts/downloads) are delivered automatically after successful payment. Wallet balance is used for in-app purchases. Please review carefully before buying; refund/exchange follows the store's notice.

        5. USER CONTENT
        You keep rights to content you post (videos, posts) but grant KENIOS the right to store and display it in the app. You are responsible for what you post.

        6. PRO PLAN
        Some advanced features require the PRO plan. Plan benefits may change; we will notify you of important updates.

        7. LIMITATION OF LIABILITY
        The app is provided "as is". To the extent permitted by law, KENIOS is not liable for indirect damages arising from use.

        8. CHANGES
        We may update these terms over time. Continued use means you accept the updated terms.

        9. CONTACT
        For questions, contact the admin via the Contact section in the store.
        """)
    }

    static func privacyBody(_ store: AppStore) -> String {
        store.t(
        """
        Cập nhật lần cuối: 2026

        1. DỮ LIỆU CHÚNG TÔI THU THẬP
        - Thông tin tài khoản: tên đăng nhập, email/số điện thoại (nếu bạn cung cấp).
        - Nội dung bạn tạo: bài đăng, video, file tải lên, tin nhắn.
        - Dữ liệu giao dịch: lịch sử mua hàng, nạp ví.
        - Dữ liệu kỹ thuật: token thiết bị (để gửi thông báo), nhật ký lỗi.

        2. MỤC ĐÍCH SỬ DỤNG
        Để cung cấp và vận hành dịch vụ: đăng nhập, giao hàng số, ví, thông báo, hỗ trợ và cải thiện ứng dụng.

        3. LƯU TRỮ
        Dữ liệu được lưu trên máy chủ do quản trị viên vận hành. Mật khẩu được băm (hash), không lưu dạng văn bản thường. Token đăng nhập lưu an toàn trong Keychain của thiết bị.

        4. CHIA SẺ
        Chúng tôi KHÔNG bán dữ liệu cá nhân. Chỉ chia sẻ khi pháp luật yêu cầu hoặc để vận hành dịch vụ (vd: cổng thanh toán, dịch vụ thông báo).

        5. QUYỀN TRÊN THIẾT BỊ
        Ứng dụng có thể xin quyền: Ảnh/Camera (đính kèm, lưu video tải về), Micro (ghi âm chuyển văn bản), Thông báo. Bạn có thể tắt trong Cài đặt iOS bất cứ lúc nào.

        6. QUYỀN CỦA BẠN
        Bạn có thể xem/sửa thông tin tài khoản, xoá nội dung đã đăng, hoặc yêu cầu xoá tài khoản qua admin.

        7. TRẺ EM
        Ứng dụng không hướng tới trẻ em dưới 13 tuổi.

        8. THAY ĐỔI
        Chính sách có thể được cập nhật; thay đổi quan trọng sẽ được thông báo trong ứng dụng.

        9. LIÊN HỆ
        Liên hệ admin qua mục Liên hệ trong cửa hàng để được hỗ trợ về quyền riêng tư.
        """,
        """
        Last updated: 2026

        1. DATA WE COLLECT
        - Account info: username, email/phone (if you provide them).
        - Content you create: posts, videos, uploaded files, messages.
        - Transaction data: purchase and wallet top-up history.
        - Technical data: device token (for notifications), error logs.

        2. HOW WE USE IT
        To provide and run the service: login, digital delivery, wallet, notifications, support and app improvement.

        3. STORAGE
        Data is stored on a server operated by the administrator. Passwords are hashed, never stored in plain text. Login tokens are stored securely in the device Keychain.

        4. SHARING
        We do NOT sell personal data. We share only when required by law or to operate the service (e.g. payment gateway, notification service).

        5. DEVICE PERMISSIONS
        The app may request: Photos/Camera (attachments, saving downloaded videos), Microphone (speech-to-text), Notifications. You can disable these in iOS Settings anytime.

        6. YOUR RIGHTS
        You can view/edit account info, delete content you posted, or request account deletion via the admin.

        7. CHILDREN
        The app is not directed to children under 13.

        8. CHANGES
        This policy may be updated; significant changes will be announced in the app.

        9. CONTACT
        Contact the admin via the Contact section in the store for privacy support.
        """)
    }
}

// ======================== Màn nội dung: hiển thị từng mục thành thẻ đẹp ========================
struct LegalDocView: View {
    let title: String
    let headerIcon: String
    let accent: Color
    let content: String
    let icons: [String]

    private struct Sec: Identifiable {
        let id = UUID()
        let num: String
        let title: String
        let body: String
    }

    // Tách nội dung: dòng "Cập nhật..." + các mục "N. TIÊU ĐỀ" kèm nội dung.
    private var parsed: (updated: String, sections: [Sec]) {
        var updated = ""
        var out: [Sec] = []
        for raw in content.components(separatedBy: "\n\n") {
            let b = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if b.isEmpty { continue }
            var lines = b.components(separatedBy: "\n")
            let head = lines[0].trimmingCharacters(in: .whitespaces)
            let low = head.lowercased()
            if low.hasPrefix("cập nhật") || low.hasPrefix("last updated") {
                updated = head; continue
            }
            var num = ""
            var titleText = head
            if let dot = head.firstIndex(of: ".") {
                let prefix = String(head[head.startIndex..<dot]).trimmingCharacters(in: .whitespaces)
                if Int(prefix) != nil {
                    num = prefix
                    titleText = String(head[head.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            lines.removeFirst()
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Sec(num: num, title: titleText, body: body))
        }
        return (updated, out)
    }

    var body: some View {
        let data = parsed
        ScrollView {
            VStack(spacing: 14) {
                // Hero
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(accent.gradient).frame(width: 62, height: 62)
                            .shadow(color: accent.opacity(0.4), radius: 9, y: 4)
                        Image(systemName: headerIcon)
                            .font(.system(size: 27, weight: .bold)).foregroundStyle(.white)
                    }
                    Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                    if !data.updated.isEmpty {
                        Text(data.updated)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(accent.opacity(0.14)))
                            .foregroundStyle(accent)
                    }
                }
                .padding(.top, 6).padding(.bottom, 2)

                ForEach(Array(data.sections.enumerated()), id: \.element.id) { idx, s in
                    card(s, icon: idx < icons.count ? icons[idx] : "doc.text.fill")
                }

                Text("KENIOS")
                    .font(.caption2.bold()).foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // Thẻ 1 mục: icon gradient + số + tiêu đề + nội dung (hỗ trợ gạch đầu dòng).
    private func card(_ s: Sec, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(accent.gradient).frame(width: 36, height: 36)
                    Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                }
                Text(s.title)
                    .font(.headline).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if !s.num.isEmpty {
                    Text(s.num)
                        .font(.caption.bold().monospacedDigit()).foregroundStyle(accent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(accent.opacity(0.12)))
                }
            }
            bodyView(s.body)
                .padding(.leading, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    @ViewBuilder private func bodyView(_ body: String) -> some View {
        let lines = body.components(separatedBy: "\n")
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("- ") {
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(accent).frame(width: 5, height: 5).padding(.top, 7)
                        Text(String(t.dropFirst(2)))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !t.isEmpty {
                    Text(t)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
