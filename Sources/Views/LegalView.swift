import SwiftUI

// ======================== Pháp lý: Điều khoản & Chính sách bảo mật ========================
struct LegalView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section {
                NavigationLink {
                    LegalDocView(title: store.t("Điều khoản sử dụng", "Terms of Use"),
                                 content: LegalView.termsBody(store))
                } label: {
                    Label(store.t("Điều khoản sử dụng", "Terms of Use"), systemImage: "doc.text")
                }
                NavigationLink {
                    LegalDocView(title: store.t("Chính sách bảo mật", "Privacy Policy"),
                                 content: LegalView.privacyBody(store))
                } label: {
                    Label(store.t("Chính sách bảo mật", "Privacy Policy"), systemImage: "lock.shield")
                }
            } footer: {
                Text(store.t("Bằng việc dùng KENIOS, bạn đồng ý với Điều khoản & Chính sách bảo mật.",
                             "By using KENIOS, you agree to the Terms & Privacy Policy."))
            }
        }
        .navigationTitle(store.t("Pháp lý", "Legal"))
        .navigationBarTitleDisplayMode(.inline)
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

struct LegalDocView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
