import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var phone = ""
    @State private var newPassword = ""
    @State private var message: String?
    @State private var connected: Bool?
    @State private var showConnections = false
    @State private var showPayment = false
    @State private var cleanupDays = 30
    @State private var cleaning = false
    // Logo & hiệu ứng app ngoài (khác cửa hàng)
    @AppStorage("appLogoEffect") private var appLogoEffect = "rainbow"
    @AppStorage("appLogoFont") private var appLogoFont = "rounded"
    @AppStorage("appLogoAnim") private var appLogoAnim = "shimmer"
    @AppStorage("defaultLaunchTab") private var defaultLaunchTab = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "gearshape.fill",
                                title: store.t("Cài đặt", "Settings"),
                                subtitle: store.t("Tài khoản · giao diện · dọn dẹp · cache",
                                                  "Account · appearance · cleanup · cache"))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // SERVER — chỉ hiện khi CHƯA cài sẵn máy chủ mặc định (Config.defaultServerURL)
                if Config.defaultServerURL.isEmpty {
                    Section(store.t("Kết nối máy chủ", "Server connection") + " (\(store.serverType))") {
                        LabeledContent("URL / IP", value: store.baseURL)
                        HStack {
                            Text(store.t("Trạng thái", "Status"))
                            Spacer()
                            if let connected {
                                Circle().fill(connected ? .green : .red).frame(width: 8, height: 8)
                                Text(connected ? store.t("Đang kết nối", "Connected") : store.t("Mất kết nối", "Disconnected"))
                                    .foregroundStyle(connected ? .green : .red)
                            } else { ProgressView() }
                        }
                        Button(store.t("Quản lý máy chủ (VPS / Hosting)", "Manage server (VPS / Hosting)")) { showConnections = true }
                    }
                }

                // ACCOUNT
                Section(store.t("Tài khoản", "Account")) {
                    LabeledContent(store.t("Tên đăng nhập", "Username"), value: store.username ?? "-")
                    HStack {
                        Text(store.t("ID của bạn", "Your ID"))
                        Spacer()
                        Text(store.publicId.isEmpty ? "—" : store.publicId)
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text(store.t("Gói", "Plan"))
                        Spacer()
                        Text(store.isPro ? "PRO" : "Free")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                    }
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(store.credits)").foregroundStyle(Theme.accent)
                    }
                    Button(store.t("Nạp credits", "Buy credits")) { showPayment = true }
                    TextField("Gmail", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField(store.t("Số điện thoại", "Phone number"), text: $phone).keyboardType(.phonePad)
                    SecureField(store.t("Đổi mật khẩu (để trống nếu không đổi)", "Change password (leave blank to keep)"), text: $newPassword)
                    Button(store.t("Lưu thay đổi", "Save changes")) { Task { await saveProfile() } }
                }

                Section(store.t("Ngôn ngữ & Giao diện", "Language & Appearance")) {
                    Picker(store.t("Ngôn ngữ", "Language"), selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) })) {
                        ForEach(kAppLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    Picker(store.t("Mở app vào tab", "Open app on tab"), selection: $defaultLaunchTab) {
                        Text(store.t("Mạng xã hội", "Social")).tag(2)
                        Text(store.t("Video", "Video")).tag(14)
                        Text(store.t("Cửa hàng", "Store")).tag(15)
                        Text(store.t("Bạn bè", "Friends")).tag(4)
                        Text(store.t("Khám phá", "Explore")).tag(16)
                    }
                    // Bộ chọn giao diện đẹp hơn — đổi tức thì (không lag)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Giao diện", "Theme")).font(.subheadline)
                        HStack(spacing: 10) {
                            themeOption("light",  "Sáng",   "Light", "sun.max.fill")
                            themeOption("dark",   "Tối",    "Dark",  "moon.fill")
                            themeOption("system", "Cân bằng","Auto",  "circle.lefthalf.filled")
                        }
                    }
                    .padding(.vertical, 4)
                }

                // ===== Tuỳ biến thương hiệu — CHỈ admin thấy (khách không thấy) =====
                if store.isAdmin {
                // ===== Logo & hiệu ứng app (ngoài cửa hàng) =====
                Section(store.t("Logo & Hiệu ứng app", "App logo & effects")) {
                    HStack { Spacer()
                        AnimatedStoreLogo(text: "KENIOS", effect: appLogoEffect,
                                          fontStyle: appLogoFont, anim: appLogoAnim, size: 30)
                        Spacer() }
                    Picker(store.t("Hiệu ứng màu", "Color effect"), selection: $appLogoEffect) {
                        ForEach(kLogoEffects, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker(store.t("Kiểu chữ (font)", "Font"), selection: $appLogoFont) {
                        ForEach(kLogoFonts, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Picker(store.t("Chuyển động", "Animation"), selection: $appLogoAnim) {
                        ForEach(kLogoAnims, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Text(store.t("Áp cho logo/thương hiệu của app (khác với cài đặt cửa hàng).",
                                 "Applies to the app's logo/branding (separate from store settings)."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ===== Màu chủ đạo =====
                Section(store.t("Màu chủ đạo của app", "App accent color")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(kAccentColors, id: \.name) { item in
                            Button {
                                store.setAccentColor(item.name)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 38, height: 38)
                                    if store.accentColorName == item.name {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                // ===== Lời chào khi mở app =====
                Section(store.t("Lời chào khi mở app", "Welcome greeting")) {
                    NavigationLink {
                        WelcomeGreetingView()
                    } label: {
                        HStack {
                            Label(store.t("Lời chào & giọng đọc", "Greeting & voice"), systemImage: "waveform.badge.mic")
                            Spacer()
                            Text(store.welcomeEnabled ? store.t("Đang bật", "On") : store.t("Tắt", "Off"))
                                .font(.caption)
                                .foregroundStyle(store.welcomeEnabled ? .green : .secondary)
                        }
                    }
                }

                // ===== Hiệu ứng logo =====
                Section(store.t("Hiệu ứng & Logo", "Effects & Logo")) {
                    Toggle(store.t("Logo có hiệu ứng động", "Animated logo"), isOn: Binding(
                        get: { store.logoAnimated },
                        set: { store.setLogoAnimated($0) }))
                    Text(store.t("Bật để logo KENIOS và logo cửa hàng có hiệu ứng chuyển động lấp lánh.",
                                 "Enable shimmering animation for the KENIOS and store logos."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                } // hết phần tuỳ biến thương hiệu (chỉ admin)

                // ===== Thông báo =====
                Section(store.t("Thông báo", "Notifications")) {
                    Button {
                        store.requestNotificationPermission()
                        message = store.t("Đã mở yêu cầu cấp quyền thông báo iOS.", "Opened iOS notification permission request.")
                    } label: {
                        Label(store.t("Bật thông báo (sản phẩm mới, cập nhật)", "Enable notifications (new products, updates)"),
                              systemImage: "bell.badge")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label(store.t("Mở Cài đặt iOS để quản lý thông báo", "Open iOS Settings to manage notifications"),
                              systemImage: "gear")
                    }
                    Text(store.t("Thông báo xuất hiện khi admin thêm sản phẩm mới hoặc có cập nhật bảo trì.",
                                 "Notifications appear when an admin adds new products or posts a maintenance update."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Dung lượng & Dọn dẹp", "Storage & Cleanup")) {
                    Picker(store.t("Xóa tin nhắn cũ hơn", "Delete messages older than"), selection: $cleanupDays) {
                        Text("7 " + store.t("ngày", "days")).tag(7)
                        Text("30 " + store.t("ngày", "days")).tag(30)
                        Text("90 " + store.t("ngày", "days")).tag(90)
                    }
                    .pickerStyle(.menu)

                    Button {
                        Task { await runCleanup() }
                    } label: {
                        HStack {
                            if cleaning {
                                ProgressView().tint(.red).padding(.trailing, 4)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text(store.t("Dọn dẹp cơ sở dữ liệu", "Clean up database"))
                        }
                        .foregroundStyle(.red)
                    }
                    .disabled(cleaning)
                }

                Section(store.t("Bộ nhớ đệm (Cache)", "Cache")) {
                    Button {
                        clearCache()
                    } label: { Label(store.t("Xoá cache của app", "Clear app cache"), systemImage: "trash") }
                }

                if let message { Text(message).foregroundStyle(.green).font(.footnote) }

                Section(store.t("Pháp lý", "Legal")) {
                    NavigationLink {
                        LegalView()
                    } label: {
                        Label(store.t("Điều khoản & Chính sách bảo mật", "Terms & Privacy Policy"), systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section {
                    Button(store.t("Đăng xuất", "Logout"), role: .destructive) {
                        dismiss()                 // đóng màn Cài đặt (sheet) ngay
                        store.logout()            // xoá phiên → về màn đăng nhập tức thì
                    }
                }
            }
            .navigationTitle(store.t("Cài đặt", "Settings"))
            .sheet(isPresented: $showConnections) { ConnectionsView() }
            .sheet(isPresented: $showPayment) { PaymentView() }
            .task {
                await store.refreshCredits()
                connected = (try? await store.api.getConfig()) != nil
            }
            .onAppear { email = store.email ?? ""; phone = store.phone ?? "" }
        }
    }

    // 1 ô chọn giao diện (sáng/tối/cân bằng) — bấm đổi ngay lập tức
    private func themeOption(_ mode: String, _ vi: String, _ en: String, _ icon: String) -> some View {
        let selected = store.themeMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { store.setThemeMode(mode) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(store.t(vi, en)).font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(selected ? store.accentColor.opacity(0.20) : Color(.secondarySystemBackground))
            .foregroundStyle(selected ? store.accentColor : .primary)
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? store.accentColor : Color.clear, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func clearCache() {
        // Xoá URLCache + thư mục Caches + tệp tạm
        URLCache.shared.removeAllCachedResponses()
        let fm = FileManager.default
        for dir in [fm.urls(for: .cachesDirectory, in: .userDomainMask).first, fm.temporaryDirectory].compactMap({ $0 }) {
            if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for u in items { try? fm.removeItem(at: u) }
            }
        }
        message = store.t("Đã xoá cache.", "Cache cleared.")
    }

    private func saveProfile() async {
        do {
            _ = try await store.api.updateProfile(email: email, phone: phone,
                                                   newPassword: newPassword.isEmpty ? nil : newPassword)
            store.updateLocalUser(email: email, phone: phone)
            newPassword = ""; message = store.t("Đã cập nhật.", "Updated.")
        } catch { message = error.localizedDescription }
    }

    private func runCleanup() async {
        cleaning = true
        message = nil
        do {
            let res = try await store.api.cleanupDatabase(days: cleanupDays)
            message = res.message
        } catch {
            message = "Lỗi: \(error.localizedDescription)"
        }
        cleaning = false
    }
}

// ============================ Lời chào khi mở app ============================
struct WelcomeGreetingView: View {
    @EnvironmentObject var store: AppStore
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var rateBinding: Double = 0.5

    private let templates = [
        "Chào mừng bạn đã đến với KENIOS. Chúc bạn một ngày tốt lành!",
        "Xin chào! Rất vui được gặp lại bạn tại KENIOS hôm nay.",
        "Kính chào quý khách! KENIOS xin chào và chúc bạn mua sắm vui vẻ.",
        "Hello! Chào mừng bạn quay trở lại. Hôm nay có gì mới tại KENIOS đấy!",
        "Chào bạn! Hãy cùng khám phá những tính năng thú vị của KENIOS nhé.",
        "Xin kính chào! Chúc bạn có một trải nghiệm tuyệt vời với KENIOS.",
    ]

    var body: some View {
        Form {
            Section {
                Toggle(store.t("Bật lời chào tự động khi mở app", "Auto-greeting on app open"), isOn: Binding(
                    get: { store.welcomeEnabled },
                    set: { store.setWelcomeEnabled($0) }))
                Text(store.t("Khi bật, app sẽ đọc lời chào bằng giọng nói mỗi khi bạn mở app lên.",
                             "When on, the app reads a spoken greeting each time you open it."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if store.welcomeEnabled {
                Section(store.t("Nội dung lời chào", "Greeting text")) {
                    TextEditor(text: Binding(
                        get: { store.welcomeText },
                        set: { store.setWelcomeText($0) }))
                        .frame(minHeight: 72)
                }

                Section(store.t("Mẫu lời chào (bấm để dùng)", "Greeting templates (tap to use)")) {
                    ForEach(templates, id: \.self) { t in
                        Button {
                            store.setWelcomeText(t)
                        } label: {
                            Text(t).font(.caption).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section(store.t("Giọng đọc", "Voice")) {
                    Picker(store.t("Chọn giọng", "Choose voice"), selection: Binding(
                        get: { store.welcomeVoiceId },
                        set: { store.setWelcomeVoiceId($0) })) {
                        Text(store.t("Chị Google (Online) — như TTS Live", "Google voice (Online) — like Live TTS")).tag("google")
                        Text(store.t("Mặc định (vi-VN tự động)", "Default (vi-VN automatic)")).tag("")
                        ForEach(voices, id: \.identifier) { v in
                            Text(WelcomeVoice.displayName(v)).tag(v.identifier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text(store.t("Giọng ✦ là giọng Enhanced (rõ, tự nhiên hơn). Cài thêm giọng trong iOS Settings > Accessibility > Spoken Content > Voices.",
                                 "✦ voices are Enhanced (clearer, more natural). Add more in iOS Settings > Accessibility > Spoken Content > Voices."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Tốc độ đọc", "Reading speed")) {
                    HStack(spacing: 10) {
                        Text("🐢").font(.caption)
                        Slider(value: $rateBinding, in: 0.3...0.65, step: 0.025)
                            .onChange(of: rateBinding) { store.setWelcomeRate(Float($0)) }
                        Text("🐇").font(.caption)
                    }
                    Text(store.t("Tốc độ", "Speed") + ": \(Int(rateBinding * 100))%  ·  " + store.t("(mặc định 50%)", "(default 50%)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Thử giọng đọc", "Test voice")) {
                    Button {
                        WelcomeVoice.shared.testSpeak(
                            text: store.welcomeText,
                            voiceId: store.welcomeVoiceId,
                            rate: Float(rateBinding))
                    } label: {
                        Label(store.t("▶  Phát thử lời chào", "▶  Play greeting"), systemImage: "play.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        WelcomeVoice.shared.stop()
                    } label: {
                        Label(store.t("■  Dừng phát", "■  Stop"), systemImage: "stop.circle")
                    }
                }
            }
        }
        .navigationTitle(store.t("Lời chào khi mở app", "Welcome greeting"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            voices = WelcomeVoice.availableVoices
            rateBinding = Double(store.welcomeRate)
        }
    }
}
