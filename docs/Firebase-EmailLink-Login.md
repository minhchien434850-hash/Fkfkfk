# Đăng nhập không mật khẩu bằng Firebase Email Link (iOS · SwiftUI)

> ⚠️ ĐỌC TRƯỚC:
> - App KENIOS **đã có** đăng nhập không mật khẩu bằng **mã OTP gửi Gmail** (backend + Brevo).
>   Firebase Email Link là cách KHÁC, dùng song song sẽ trùng chức năng.
> - **Firebase Dynamic Links đã ngừng hoạt động (08/2025).** Luồng email-link kiểu cũ dựa vào
>   Dynamic Links không còn dùng được. Phải dùng **Universal Links (Associated Domains)** +
>   tự host file `apple-app-site-association` trên 1 domain của bạn để link trong Gmail mở lại app.
> - Tài liệu này KHÔNG được tự gắn vào app build tự động (để không làm hỏng build GitHub Actions).
>   Bạn làm theo khi đã sẵn sàng thêm Firebase SDK + `GoogleService-Info.plist`.

---

## 1) Cấu hình trên Firebase Console

1. Vào https://console.firebase.google.com → **Add project** → tạo project.
2. **Project settings → General → Your apps → Add app → iOS**:
   - Nhập **Bundle ID** đúng bằng app của bạn: `com.kenios.codebox`.
   - Tải về **`GoogleService-Info.plist`** (sẽ kéo vào Xcode ở bước 2).
3. Vào **Build → Authentication → Get started**.
4. Tab **Sign-in method → Add new provider → Email/Password →** BẬT cả 2 công tắc:
   - **Email/Password**: Enable
   - **Email link (passwordless sign-in)**: **Enable** ← bắt buộc cho tính năng này.
5. Tab **Authentication → Settings → Authorized domains**: thêm domain bạn sẽ dùng làm
   "continue URL" (ví dụ `kenios-login.web.app` nếu dùng Firebase Hosting, hoặc domain riêng).

---

## 2) Cấu hình trong Xcode / project.yml

### 2.1 Thêm `GoogleService-Info.plist`
- Kéo file vừa tải vào thư mục `Sources/` của dự án (cùng cấp `Info.plist`).
- ⚠️ KHÔNG commit file này lên repo công khai. Thêm vào `.gitignore`:
  ```
  Sources/GoogleService-Info.plist
  ```

### 2.2 Thêm Firebase SDK (vì dự án dùng XcodeGen → khai báo trong `project.yml`)
Thêm vào `project.yml`:
```yaml
packages:
  Firebase:
    url: https://github.com/firebase/firebase-ios-sdk.git
    minVersion: 11.0.0

targets:
  KENIOS:
    dependencies:
      - package: Firebase
        product: FirebaseAuth
```
Rồi chạy lại `xcodegen generate`.
(Nếu dùng Xcode trực tiếp: File → Add Packages → dán URL trên → chọn **FirebaseAuth**.)

### 2.3 Associated Domains (để link trong Gmail mở lại app — thay cho Dynamic Links đã chết)
- Trong `project.yml`, phần `entitlements` của target, thêm:
```yaml
entitlements:
  path: Sources/KENIOS.entitlements
  properties:
    com.apple.developer.associated-domains:
      - applinks:kenios-login.web.app   # đổi thành domain bạn host
```
- Trên domain đó, host file `/.well-known/apple-app-site-association` (KHÔNG có đuôi .json,
  trả về `Content-Type: application/json`):
```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAMID.com.kenios.codebox",
        "paths": [ "/finishSignIn*" ]
      }
    ]
  }
}
```
  (Thay `TEAMID` bằng Apple Developer Team ID của bạn.)

### 2.4 (Tuỳ chọn) URL Scheme dự phòng
Nếu chưa có domain để làm Universal Link, có thể dùng URL scheme tạm để test trên máy thật:
- `project.yml → info.properties`:
```yaml
CFBundleURLTypes:
  - CFBundleURLSchemes:
      - keniosauth
```
- Khi đó `ActionCodeSettings.url` trỏ về trang web trung gian của bạn, trang đó redirect sang
  `keniosauth://finishSignIn?...`. (Universal Link vẫn là cách chuẩn & mượt hơn.)

---

## 3) Mã nguồn Swift (SwiftUI) — Clean Code

### 3.1 Khởi tạo Firebase — file `Sources/KENIOSApp.swift` (hoặc file `@main App` của bạn)
```swift
import SwiftUI
import FirebaseCore          // để gọi FirebaseApp.configure()

@main
struct KENIOSApp: App {
    // Đăng ký một AppDelegate tối giản chỉ để cấu hình Firebase lúc khởi động
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Bộ xử lý đăng nhập email-link dùng chung toàn app
    @StateObject private var emailAuth = EmailLinkAuth()

    var body: some Scene {
        WindowGroup {
            EmailLinkLoginView()
                .environmentObject(emailAuth)
                // (3.3) Khi app được MỞ LẠI từ link trong Gmail → hoàn tất đăng nhập
                .onOpenURL { url in
                    emailAuth.handleLink(url)
                }
        }
    }
}

// AppDelegate tối giản: chỉ cấu hình Firebase
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()   // đọc GoogleService-Info.plist và khởi tạo Firebase
        return true
    }
}
```

### 3.2 + 3.3 Bộ xử lý đăng nhập — file MỚI `Sources/EmailLinkAuth.swift`
```swift
import Foundation
import FirebaseAuth

/// Quản lý đăng nhập KHÔNG MẬT KHẨU bằng link gửi qua Gmail (Firebase Email Link).
final class EmailLinkAuth: ObservableObject {

    /// Thông báo trạng thái để hiển thị ra giao diện.
    @Published var status: String = ""
    /// true khi đăng nhập thành công (để chuyển màn).
    @Published var isSignedIn: Bool = false

    /// Khoá lưu email tạm trong UserDefaults.
    /// VÌ SAO PHẢI LƯU: khi khách bấm link trong Gmail, app mở lại nhưng Firebase CẦN biết
    /// email nào đang đăng nhập để đối chiếu với link. Link không chứa sẵn email (vì lý do bảo mật),
    /// nên ta lưu email lúc bấm "Nhận link" rồi lấy lại lúc app mở từ link.
    private let emailKey = "emailForSignIn"

    // ===== (3.2) GỬI LINK XÁC THỰC ĐẾN EMAIL =====
    func sendSignInLink(to rawEmail: String) {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { status = "Email không hợp lệ."; return }

        // Cấu hình link xác thực
        let settings = ActionCodeSettings()
        // URL phải nằm trong "Authorized domains" của Firebase. Đây là trang khách sẽ tới khi bấm link.
        settings.url = URL(string: "https://kenios-login.web.app/finishSignIn")
        // BẮT BUỘC = true để khi bấm link sẽ mở LẠI APP (không chỉ mở web).
        settings.handleCodeInApp = true
        // Bundle ID của app (để Firebase biết mở app iOS nào).
        if let bundleID = Bundle.main.bundleIdentifier {
            settings.setIOSBundleID(bundleID)
        }

        status = "Đang gửi link tới \(email)…"
        Auth.auth().sendSignInLink(toEmail: email, actionCodeSettings: settings) { [weak self] error in
            guard let self else { return }
            if let error = error {
                self.status = "Lỗi gửi link: \(error.localizedDescription)"
                return
            }
            // Lưu email để đối chiếu khi app mở lại từ link (xem giải thích ở trên).
            UserDefaults.standard.set(email, forKey: self.emailKey)
            self.status = "✅ Đã gửi link tới \(email). Mở Gmail và bấm vào link để đăng nhập."
        }
    }

    // ===== (3.3) HOÀN TẤT ĐĂNG NHẬP KHI APP MỞ LẠI TỪ LINK =====
    func handleLink(_ url: URL) {
        let link = url.absoluteString
        // Chỉ xử lý nếu đây đúng là link đăng nhập của Firebase.
        guard Auth.auth().isSignIn(withEmailLink: link) else { return }

        // Lấy lại email đã lưu lúc gửi link.
        guard let email = UserDefaults.standard.string(forKey: emailKey) else {
            status = "Không tìm thấy email đã lưu. Vui lòng nhập lại email trên máy này."
            return
        }

        status = "Đang xác thực…"
        Auth.auth().signIn(withEmail: email, link: link) { [weak self] result, error in
            guard let self else { return }
            if let error = error {
                self.status = "Đăng nhập thất bại: \(error.localizedDescription)"
                return
            }
            // Thành công → xoá email tạm, cập nhật trạng thái.
            UserDefaults.standard.removeObject(forKey: self.emailKey)
            self.isSignedIn = true
            self.status = "🎉 Đăng nhập thành công: \(result?.user.email ?? email)"
        }
    }

    /// Đăng xuất (tuỳ chọn).
    func signOut() {
        try? Auth.auth().signOut()
        isSignedIn = false
        status = "Đã đăng xuất."
    }
}
```

### 3.4 Giao diện mẫu — file MỚI `Sources/EmailLinkLoginView.swift`
```swift
import SwiftUI

struct EmailLinkLoginView: View {
    @EnvironmentObject var auth: EmailLinkAuth
    @State private var email: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Đăng nhập bằng Email")
                .font(.title2.bold())
            Text("Nhập Gmail, chúng tôi gửi link đăng nhập. Không cần mật khẩu.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Ô nhập email
            TextField("you@gmail.com", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Nút nhận link
            Button {
                auth.sendSignInLink(to: email)
            } label: {
                Text("Nhận link đăng nhập")
                    .frame(maxWidth: .infinity).padding()
                    .background(.blue).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(email.isEmpty)

            // Thông báo trạng thái
            if !auth.status.isEmpty {
                Text(auth.status)
                    .font(.callout)
                    .foregroundStyle(auth.isSignedIn ? .green : .secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
    }
}
```

---

## 4) Luồng hoạt động tóm tắt
1. Khách nhập Gmail → bấm **Nhận link** → `sendSignInLink` gửi link + lưu email vào UserDefaults.
2. Khách mở Gmail trên ĐÚNG máy đó → bấm link.
3. Universal Link mở lại app → SwiftUI gọi `.onOpenURL` → `handleLink(url)`.
4. Firebase đối chiếu email đã lưu với link → đăng nhập thành công.

## 5) Lỗi thường gặp
- **Bấm link chỉ mở web, không mở app** → Associated Domains/AASA chưa đúng, hoặc `handleCodeInApp` chưa bật.
- **"Không tìm thấy email đã lưu"** → khách bấm link trên MÁY KHÁC (UserDefaults không có email). Cho khách nhập lại email trên máy đang mở app.
- **Domain not authorized** → thêm domain của `settings.url` vào Authorized domains trong Firebase.
- **Build lỗi `No such module 'FirebaseAuth'`** → chưa thêm package FirebaseAuth (mục 2.2).
