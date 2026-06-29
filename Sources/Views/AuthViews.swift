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
    @State private var googleClientId = ""   // lấy từ máy chủ; rỗng = ẩn nút Google
    @State private var googleLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 116, height: 116)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1.5)
                        )
                        .shadow(color: Theme.purple.opacity(0.55), radius: 26, y: 12)
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

                    // Đăng nhập KHÔNG MẬT KHẨU bằng mã gửi Gmail/SĐT (dùng OTP sẵn có — không trùng login thường)
                    NavigationLink { OtpLoginView() } label: {
                        Label(store.t("Đăng nhập bằng mã Gmail (không mật khẩu)", "Login with Gmail code (passwordless)"),
                              systemImage: "envelope.badge.fill")
                            .font(.subheadline).frame(maxWidth: .infinity).padding()
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.5)))
                    }.padding(.horizontal)

                    // Đăng nhập bằng tài khoản Google (ASWebAuthenticationSession, không cần SDK).
                    // Chỉ hiện khi máy chủ đã cấu hình Google Client ID.
                    if !googleClientId.isEmpty {
                        Button { Task { await doGoogleLogin() } } label: {
                            HStack {
                                if googleLoading { ProgressView().padding(.trailing, 4) }
                                Image(systemName: "g.circle.fill")
                                Text(store.t("Đăng nhập bằng Google", "Sign in with Google")).bold()
                            }
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(.systemBackground))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.secondary.opacity(0.4)))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .disabled(googleLoading)
                        .padding(.horizontal)
                    }

                    NavigationLink { LegalView() } label: {
                        Text(store.t("Điều khoản & Chính sách bảo mật", "Terms & Privacy Policy"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 4)

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
            .task { await loadGoogleClientId() }
        }
    }

    /// Lấy Google Client ID từ máy chủ để quyết định có hiện nút "Đăng nhập bằng Google".
    private func loadGoogleClientId() async {
        if let cfg = try? await store.api.storeConfig() {
            googleClientId = cfg.googleClientId ?? ""
        }
    }

    /// Đăng nhập bằng Google: lấy id_token rồi gửi máy chủ xác thực.
    private func doGoogleLogin() async {
        googleLoading = true; error = nil
        do {
            let idToken = try await GoogleOAuth.shared.signInIdToken(clientID: googleClientId)
            let resp = try await store.api.googleLogin(idToken: idToken, deviceId: store.deviceId)
            store.setAuth(resp)
            await store.loadProviders(); await store.loadKeys()
        } catch { self.error = error.localizedDescription }
        googleLoading = false
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
    @State private var method = "email"   // "email" | "phone"
    @State private var email = ""
    @State private var phone = ""
    @State private var loading = false
    @State private var error: String?
    @State private var registered = false

    // OTP — mã xác nhận (email hoặc SMS)
    @State private var codeSent = false
    @State private var code = ""
    @State private var sendingCode = false
    @State private var otpInfo: String?

    private var isEmail: Bool { method == "email" }
    private var emailValid: Bool { email.contains("@") && email.contains(".") }
    private var phoneValid: Bool { phone.filter(\.isNumber).count >= 8 }
    private var identValid: Bool { isEmail ? emailValid : phoneValid }
    private var canRegister: Bool {
        username.count >= 3 && password.count >= 6 && identValid && codeSent && code.count >= 4
    }

    var body: some View {
        Form {
            Section(store.t("Tài khoản", "Account")) {
                TextField(store.t("Username * (≥3 ký tự)", "Username * (≥3 chars)"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                SecureField(store.t("Mật khẩu * (≥6 ký tự)", "Password * (≥6 chars)"), text: $password)
                    .textContentType(.newPassword)
            }

            Section(store.t("Đăng ký bằng", "Register with")) {
                Picker("", selection: $method) {
                    Text("Gmail").tag("email")
                    Text(store.t("Số điện thoại", "Phone")).tag("phone")
                }
                .pickerStyle(.segmented)
                .onChange(of: method) { _ in codeSent = false; code = ""; otpInfo = nil; error = nil }

                if isEmail {
                    TextField(store.t("Nhập Gmail của bạn", "Enter your Gmail"), text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        .autocorrectionDisabled().textContentType(.emailAddress)
                } else {
                    TextField(store.t("Nhập số điện thoại", "Enter phone number"), text: $phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                }

                // Gửi mã + nhập mã
                Button {
                    Task { await sendCode() }
                } label: {
                    HStack {
                        if sendingCode { ProgressView().padding(.trailing, 6) }
                        Image(systemName: "paperplane.fill")
                        Text(codeSent ? store.t("Gửi lại mã", "Resend code")
                                      : store.t("Gửi mã xác nhận", "Send verification code"))
                    }
                }
                .disabled(sendingCode || !identValid)

                if codeSent {
                    TextField(store.t("Nhập mã 6 số", "Enter 6-digit code"), text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                }
                if let otpInfo {
                    Text(otpInfo).font(.caption2).foregroundStyle(.secondary)
                }
                Text(isEmail
                     ? store.t("Chọn Gmail thì không cần số điện thoại.", "With Gmail, no phone needed.")
                     : store.t("Chọn số điện thoại thì không cần Gmail.", "With phone, no Gmail needed."))
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
                .disabled(loading || registered || !canRegister)
            }
        }
        .navigationTitle(store.t("Đăng ký", "Register"))
    }

    private func sendCode() async {
        sendingCode = true; error = nil; otpInfo = nil
        do {
            let r = isEmail ? try await store.api.sendOtp(email: email)
                            : try await store.api.sendOtp(phone: phone)
            codeSent = true
            let dest = isEmail ? email : phone
            switch r.channel {
            case "external":
                otpInfo = isEmail
                    ? store.t("Đã gửi mã tới \(dest). Kiểm tra hộp thư (cả Spam).", "Code sent to \(dest). Check inbox/Spam.")
                    : store.t("Đã gửi mã SMS tới \(dest).", "SMS code sent to \(dest).")
            case "internal":
                otpInfo = store.t("Đã gửi mã vào hộp thư \(dest).", "Code sent to \(dest).")
            default:
                otpInfo = r.hint ?? store.t("Chưa gửi được mã. Kiểm tra cấu hình máy chủ.",
                                            "Couldn't send code. Check server config.")
            }
            if let dbg = r.debugCode { otpInfo = store.t("Mã (chế độ thử): \(dbg)", "Code (debug): \(dbg)") }
        } catch { self.error = error.localizedDescription }
        sendingCode = false
    }

    private func doRegister() async {
        loading = true; error = nil
        do {
            // Gửi đúng phương thức đã chọn + mã xác nhận (bắt buộc)
            let em = isEmail ? email : ""
            let ph = isEmail ? "" : phone
            _ = try await store.api.register(username, password, email: em, phone: ph, code: code, deviceId: store.deviceId)
            UserDefaults.standard.set(username, forKey: "pendingLoginUser")
            registered = true
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()   // quay về màn đăng nhập
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

// ===== Đăng nhập KHÔNG MẬT KHẨU bằng mã OTP (Gmail/SĐT) — tái dùng hệ thống OTP có sẵn =====
struct OtpLoginView: View {
    @EnvironmentObject var store: AppStore
    @State private var method = "email"   // "email" | "phone"
    @State private var email = ""
    @State private var phone = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var sendingCode = false
    @State private var loading = false
    @State private var otpInfo: String?
    @State private var error: String?

    private var isEmail: Bool { method == "email" }
    private var emailValid: Bool { email.contains("@") && email.contains(".") }
    private var phoneValid: Bool { phone.filter(\.isNumber).count >= 8 }
    private var identValid: Bool { isEmail ? emailValid : phoneValid }
    private var canLogin: Bool { identValid && codeSent && code.count >= 4 }

    var body: some View {
        Form {
            Section {
                Picker("", selection: $method) {
                    Text("Gmail").tag("email")
                    Text(store.t("Số điện thoại", "Phone")).tag("phone")
                }
                .pickerStyle(.segmented)
                .onChange(of: method) { _ in codeSent = false; code = ""; otpInfo = nil; error = nil }

                if isEmail {
                    TextField(store.t("Nhập Gmail của bạn", "Enter your Gmail"), text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                        .autocorrectionDisabled().textContentType(.emailAddress)
                } else {
                    TextField(store.t("Nhập số điện thoại", "Enter phone number"), text: $phone)
                        .keyboardType(.phonePad).textContentType(.telephoneNumber)
                }

                Button {
                    Task { await sendCode() }
                } label: {
                    HStack {
                        if sendingCode { ProgressView().padding(.trailing, 6) }
                        Image(systemName: "paperplane.fill")
                        Text(codeSent ? store.t("Gửi lại mã", "Resend code")
                                      : store.t("Gửi mã đăng nhập", "Send login code"))
                    }
                }
                .disabled(sendingCode || !identValid)

                if codeSent {
                    TextField(store.t("Nhập mã 6 số", "Enter 6-digit code"), text: $code)
                        .keyboardType(.numberPad).textContentType(.oneTimeCode)
                }
                if let otpInfo { Text(otpInfo).font(.caption2).foregroundStyle(.secondary) }
            } header: {
                Text(store.t("Đăng nhập bằng mã (không cần mật khẩu)", "Login with code (passwordless)"))
            } footer: {
                Text(store.t("Nhập Gmail/SĐT → nhận mã → đăng nhập. Chưa có tài khoản sẽ tự tạo.",
                             "Enter Gmail/phone → get code → log in. A new account is created if none exists."))
            }

            if let error { Text(error).foregroundStyle(.red).font(.footnote) }

            Section {
                Button { Task { await doOtpLogin() } } label: {
                    HStack {
                        if loading { ProgressView().padding(.trailing, 6) }
                        Text(store.t("Đăng nhập", "Login")).bold()
                    }
                }
                .disabled(loading || !canLogin)
            }
        }
        .navigationTitle(store.t("Đăng nhập bằng mã", "Login with code"))
    }

    private func sendCode() async {
        sendingCode = true; error = nil; otpInfo = nil
        do {
            let r = isEmail ? try await store.api.sendOtp(email: email, purpose: "login")
                            : try await store.api.sendOtp(phone: phone, purpose: "login")
            codeSent = true
            let dest = isEmail ? email : phone
            switch r.channel {
            case "external":
                otpInfo = store.t("Đã gửi mã tới \(dest). Kiểm tra hộp thư (cả Spam).", "Code sent to \(dest). Check inbox/Spam.")
            case "internal":
                otpInfo = store.t("Đã gửi mã vào hộp thư \(dest).", "Code sent to \(dest).")
            default:
                otpInfo = r.hint ?? store.t("Chưa gửi được mã. Kiểm tra cấu hình máy chủ.", "Couldn't send code. Check server config.")
            }
            if let dbg = r.debugCode { otpInfo = store.t("Mã (chế độ thử): \(dbg)", "Code (debug): \(dbg)") }
        } catch { self.error = error.localizedDescription }
        sendingCode = false
    }

    private func doOtpLogin() async {
        loading = true; error = nil
        do {
            let em = isEmail ? email : ""
            let ph = isEmail ? "" : phone
            let resp = try await store.api.loginOtp(email: em, phone: ph, code: code, deviceId: store.deviceId)
            store.setAuth(resp)
            await store.loadProviders(); await store.loadKeys()
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
