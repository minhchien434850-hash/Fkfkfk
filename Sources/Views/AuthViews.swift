import SwiftUI

struct LoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var username = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?
    @State private var goRegister = false
    @State private var showConnections = false
    @State private var remember = false
    @State private var didAutoTry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(Theme.heroGradient)
                            .frame(width: 116, height: 116)
                            .shadow(color: Theme.purple.opacity(0.55), radius: 26, y: 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 30, style: .continuous)
                                    .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: 1.5)
                            )
                        Text("🦊")
                            .font(.system(size: 66))
                            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    }
                    .padding(.top, 52)

                    RainbowText(text: "KENIOS", size: 40)
                    Text(store.t("Mạng xã hội · Video · Giải trí · Công cụ", "Social · Video · Entertainment · Tools"))
                        .font(.subheadline).foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Username").font(.caption).foregroundStyle(.secondary)
                        TextField("kenios_user", text: $username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .textContentType(.username)   // iOS gợi ý lưu/điền từ iCloud Keychain
                            .padding(12).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(store.t("Mật khẩu", "Password")).font(.caption).foregroundStyle(.secondary)
                        SecureField("••••••••", text: $password)
                            .textContentType(.password)   // bật lưu mật khẩu vào Apple ID / trình quản lý
                            .submitLabel(.go)
                            .onSubmit { Task { await doLogin() } }
                            .padding(12).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Toggle(isOn: $remember) {
                            Label(store.t("Nhớ tài khoản & mật khẩu", "Remember username & password"), systemImage: "lock.rotation")
                                .font(.subheadline)
                        }.tint(Theme.accent).padding(.top, 4)
                    }.padding(.horizontal)

                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }

                    Button { Task { await doLogin() } } label: {
                        HStack {
                            if loading { ProgressView().tint(.white).padding(.trailing, 6) }
                            Text(store.t("Đăng nhập", "Login")).bold().frame(maxWidth: .infinity)
                        }.padding().background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }.padding(.horizontal).disabled(loading)

                    NavigationLink(store.t("Quên mật khẩu?", "Forgot password?")) { ForgotPasswordView() }
                        .font(.subheadline).foregroundStyle(Theme.accent)

                    HStack { Rectangle().frame(height: 1).opacity(0.2); Text(store.t("hoặc", "or")).font(.caption).foregroundStyle(.secondary); Rectangle().frame(height: 1).opacity(0.2) }
                        .padding(.horizontal)

                    NavigationLink { RegisterView() } label: {
                        Text(store.t("Tạo tài khoản mới", "Create new account")).frame(maxWidth: .infinity).padding()
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.4)))
                    }.padding(.horizontal)

                    // Ẩn hoàn toàn phần liên kết máy chủ khi đã cài sẵn URL mặc định (Config.defaultServerURL)
                    if Config.defaultServerURL.isEmpty {
                        if store.baseURL.isEmpty {
                            NavigationLink { ServerSetupView() } label: {
                                HStack {
                                    Image(systemName: "globe").foregroundStyle(.orange)
                                    Text(store.t("Chưa có máy chủ — bấm để kết nối", "No server — tap to connect")).font(.caption)
                                }
                                .padding().frame(maxWidth: .infinity)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }.padding(.horizontal)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "globe").foregroundStyle(Theme.accent)
                                VStack(alignment: .leading) {
                                    Text(store.t("Máy chủ", "Server") + " \(store.serverType)").font(.caption).foregroundStyle(.secondary)
                                    Text(store.baseURL).font(.caption).foregroundStyle(Theme.accent).lineLimit(1)
                                }
                                Spacer()
                                Button(store.t("Đổi", "Change")) { showConnections = true }.font(.caption)
                            }
                            .padding().background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal)
                        }
                    }
                }
            }
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .task { await prepareLogin() }
        }
    }

    /// Khi mở màn đăng nhập: điền sẵn tài khoản vừa đăng ký (nếu có) hoặc
    /// tài khoản đã "nhớ" — và tự đăng nhập nếu bật nhớ mật khẩu.
    private func prepareLogin() async {
        guard !didAutoTry else { return }
        didAutoTry = true
        remember = store.rememberLogin
        let d = UserDefaults.standard
        if let justRegistered = d.string(forKey: "pendingLoginUser"), !justRegistered.isEmpty {
            username = justRegistered
            d.removeObject(forKey: "pendingLoginUser")
            return
        }
        if remember && !store.savedUsername.isEmpty {
            username = store.savedUsername
            password = store.savedPassword
            // Tự đăng nhập khi mở app; nhưng KHÔNG tự vào lại ngay sau khi vừa đăng xuất
            let skip = store.suppressAutoLogin
            store.suppressAutoLogin = false
            if !password.isEmpty && !skip { await doLogin() }
        } else {
            store.suppressAutoLogin = false
        }
    }

    private func doLogin() async {
        loading = true; error = nil
        do {
            let resp = try await store.api.login(username, password)
            // Nhớ / quên tài khoản theo lựa chọn
            if remember { store.saveCredentials(username, password) }
            else { store.forgetCredentials() }
            store.setAuth(resp)
            await store.loadProviders(); await store.loadKeys()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct RegisterView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var loading = false
    @State private var error: String?
    @State private var registered = false

    // OTP — mã xác nhận email
    @State private var codeSent = false
    @State private var code = ""
    @State private var sendingCode = false
    @State private var otpInfo: String?

    private var emailValid: Bool { email.contains("@") && email.contains(".") }

    var body: some View {
        Form {
            Section(store.t("Tạo tài khoản", "Create account")) {
                TextField(store.t("Username * (≥3 ký tự)", "Username * (≥3 chars)"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                SecureField(store.t("Mật khẩu * (≥6 ký tự)", "Password * (≥6 chars)"), text: $password)
                    .textContentType(.newPassword)   // iOS gợi ý lưu mật khẩu mới vào Apple ID
                TextField(store.t("Gmail (tuỳ chọn)", "Gmail (optional)"), text: $email)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                TextField(store.t("Số điện thoại (tuỳ chọn)", "Phone number (optional)"), text: $phone).keyboardType(.phonePad)
                Text(store.t("Chỉ cần SĐT hoặc Gmail là được — không cần mã xác nhận.",
                             "Just a phone or Gmail is enough — no verification code needed."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if registered {
                Text(store.t("Tạo tài khoản thành công! Đang chuyển về màn đăng nhập…",
                             "Account created! Returning to login…"))
                    .foregroundStyle(.green).font(.footnote)
            }
            Section {
                Button { Task { await doRegister() } } label: {
                    HStack { if loading { ProgressView().padding(.trailing, 6) }; Text(store.t("Tạo tài khoản", "Create account")) }
                }
                .disabled(loading || registered)
            }
        }
        .navigationTitle(store.t("Đăng ký", "Register"))
    }

    private func sendCode() async {
        sendingCode = true; error = nil; otpInfo = nil
        do {
            let r = try await store.api.sendOtp(email: email)
            codeSent = true
            switch r.channel {
            case "external": otpInfo = "Đã gửi mã tới \(email). Kiểm tra hộp thư (cả mục Spam)."
            case "internal": otpInfo = "Đã gửi mã vào hộp thư \(email)."
            default:
                otpInfo = r.hint ?? "Chưa gửi được mã. Kiểm tra cấu hình email trên máy chủ."
            }
            if let dbg = r.debugCode { otpInfo = "Mã (chế độ thử): \(dbg)" }
        } catch { self.error = error.localizedDescription }
        sendingCode = false
    }

    private func doRegister() async {
        loading = true; error = nil
        do {
            // chỉ gửi mã nếu người dùng thực sự đã nhập (không bắt buộc)
            let otp = (codeSent && code.count >= 4) ? code : nil
            // Tạo tài khoản nhưng KHÔNG tự đăng nhập — quay lại màn đăng nhập.
            _ = try await store.api.register(username, password, email: email, phone: phone, code: otp)
            // Ghi tên vừa tạo để màn đăng nhập điền sẵn
            UserDefaults.standard.set(username, forKey: "pendingLoginUser")
            registered = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()   // quay về màn đăng nhập để người dùng đăng nhập
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct ForgotPasswordView: View {
    @EnvironmentObject var store: AppStore
    @State private var username = ""
    @State private var token = ""
    @State private var newPassword = ""
    @State private var info: String?
    @State private var error: String?

    var body: some View {
        Form {
            Section(store.t("Bước 1 · Lấy mã đặt lại", "Step 1 · Get reset code")) {
                TextField(store.t("Tên đăng nhập", "Username"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button(store.t("Gửi yêu cầu", "Send request")) { Task { await getCode() } }
            }
            Section(store.t("Bước 2 · Đặt mật khẩu mới", "Step 2 · Set new password")) {
                TextField(store.t("Mã đặt lại", "Reset code"), text: $token).autocorrectionDisabled()
                SecureField(store.t("Mật khẩu mới (≥6 ký tự)", "New password (≥6 chars)"), text: $newPassword)
                Button(store.t("Đổi mật khẩu", "Change password")) { Task { await doReset() } }
            }
            if let info { Text(info).foregroundStyle(.green).font(.footnote) }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .navigationTitle(store.t("Quên mật khẩu", "Forgot password"))
    }

    private func getCode() async {
        error = nil; info = nil
        do {
            let r = try await store.api.forgot(username)
            if let t = r.resetToken { token = t }
            info = r.message
        } catch { self.error = error.localizedDescription }
    }
    private func doReset() async {
        error = nil; info = nil
        do { let r = try await store.api.reset(token, newPassword); info = r.message }
        catch { self.error = error.localizedDescription }
    }
}
