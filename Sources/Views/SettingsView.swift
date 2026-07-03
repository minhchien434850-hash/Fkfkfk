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
                                                  "Account · appearance · cleanup · cache"),
                                useLogo: true)
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
                        Text(store.publicId.isEmpty ? "—" : store.displayPublicId)
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text(store.t("Gói", "Plan"))
                        Spacer()
                        Text(store.isPro ? "PRO" : "Free")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                    }
                    if store.isPro, let exp = store.planExpiryText {
                        HStack {
                            Text(store.t("Hết hạn", "Expires"))
                            Spacer()
                            Text(exp).foregroundStyle(.secondary)
                        }
                    } else if store.isPro && !store.isAdmin {
                        HStack {
                            Text(store.t("Hạn dùng", "Validity"))
                            Spacer()
                            Text(store.t("Vĩnh viễn", "Lifetime")).foregroundStyle(.secondary)
                        }
                    }
                    Button(store.isPro ? store.t("Gia hạn / Đổi gói", "Renew / Change plan")
                                       : store.t("Nâng cấp gói", "Upgrade plan")) { showPayment = true }
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

                // ===== Thông báo (CHỈ admin thấy) =====
                // Khách hàng KHÔNG thấy mục này; app đã tự xin quyền thông báo lúc
                // khởi động (AppDelegate) nên với khách mặc định là BẬT.
                if store.isAdmin {
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

                // §5 — Thông tin ứng dụng (công khai, tách khỏi trang quản trị)
                Section(store.t("Thông tin ứng dụng", "App Information")) {
                    NavigationLink {
                        AppInfoView()
                    } label: {
                        Label(store.t("Thông tin ứng dụng", "App Information"), systemImage: "info.circle")
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

    // ===== Giọng chào TOÀN CỤC (admin đặt cho MỌI người) — gộp từ mục Quản trị =====
    @State private var gEnabled = true
    @State private var gText = "Chào mừng bạn đã đến với KENIOS. Chúc bạn một ngày tốt lành!"
    @State private var gRate: Double = 0.5
    @State private var gLogoName = ""
    @State private var gLogoUrl = ""
    @State private var gBannerType = "image"
    @State private var gBannerUrl = ""
    @State private var gLoaded = false
    @State private var gSaving = false
    @State private var gMessage: String?
    @State private var gIsError = false
    // ===== Gộp thêm: Lời chào POPUP (chữ) + Thông báo cập nhật phiên bản (admin) =====
    @State private var gPopupEnabled = false
    @State private var gPopupTitle = ""
    @State private var gPopupText = ""
    @State private var gVersion = ""
    @State private var gUpdateUrl = ""
    @State private var gUpdateMsg = ""

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
            // 1 công tắc DUY NHẤT: admin = áp cho MỌI người; người thường = lời chào cá nhân.
            Section {
                Toggle(store.isAdmin
                       ? store.t("Bật lời chào khi mở app (áp cho MỌI người)",
                                 "Greeting on app open (ALL users)")
                       : store.t("Bật lời chào tự động khi mở app", "Auto-greeting on app open"),
                       isOn: Binding(
                    get: { store.welcomeEnabled },
                    set: { on in
                        store.setWelcomeEnabled(on)
                        if store.isAdmin { gEnabled = on }
                    }))
                Text(store.isAdmin
                     ? store.t("Khi bật, MỌI người dùng đều nghe lời chào này mỗi khi mở app. Nhớ bấm Lưu ở cuối để áp dụng cho mọi người.",
                               "When on, EVERY user hears this greeting on app open. Tap Save below to apply to everyone.")
                     : store.t("Khi bật, app sẽ đọc lời chào bằng giọng nói mỗi khi bạn mở app lên.",
                               "When on, the app reads a spoken greeting each time you open it."))
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if store.welcomeEnabled {
                Section(store.t("Nội dung lời chào", "Greeting text")) {
                    TextEditor(text: Binding(
                        get: { store.welcomeText },
                        set: { s in
                            store.setWelcomeText(s)
                            if store.isAdmin { gText = s }
                        }))
                        .frame(minHeight: 72)
                }

                Section(store.t("Mẫu lời chào (bấm để dùng)", "Greeting templates (tap to use)")) {
                    ForEach(templates, id: \.self) { t in
                        Button {
                            store.setWelcomeText(t)
                            if store.isAdmin { gText = t }
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
                            .onChange(of: rateBinding) {
                                store.setWelcomeRate(Float($0))
                                if store.isAdmin { gRate = $0 }
                            }
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

            // ===== Khu vực Admin (giọng chào toàn cục đã GỘP vào công tắc ở trên) =====
            if store.isAdmin {
                // ===== Lời chào POPUP (chữ) toàn cục =====
                Section {
                    Toggle(store.t("Bật lời chào popup (chữ)", "Enable welcome popup (text)"), isOn: $gPopupEnabled)
                    if gPopupEnabled {
                        TextField(store.t("Tiêu đề (vd: Chào mừng!)", "Title (e.g. Welcome!)"), text: $gPopupTitle)
                        TextField(store.t("Nội dung popup cho mọi khách", "Popup text for all users"),
                                  text: $gPopupText, axis: .vertical).lineLimit(2...5)
                    }
                } header: {
                    Text(store.t("💬 Lời chào popup — Admin", "💬 Welcome popup — Admin"))
                } footer: {
                    Text(store.t("Popup chữ hiện 1 lần khi MỌI người mở app (khác giọng nói ở trên).",
                                 "Text popup shown once when EVERY user opens the app (separate from the voice above)."))
                        .font(.caption2)
                }

                // ===== Thông báo cập nhật phiên bản =====
                Section {
                    TextField(store.t("Phiên bản mới nhất (vd 3.1)", "Latest version (e.g. 3.1)"), text: $gVersion)
                        .keyboardType(.decimalPad)
                    TextField(store.t("Link tải/cập nhật (https://...)", "Update link (https://...)"), text: $gUpdateUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField(store.t("Lời nhắn cập nhật (tuỳ chọn)", "Update message (optional)"),
                              text: $gUpdateMsg, axis: .vertical).lineLimit(1...3)
                } header: {
                    Text(store.t("🆕 Thông báo cập nhật phiên bản — Admin", "🆕 Version update notice — Admin"))
                } footer: {
                    Text(store.t("Bản mới > phiên bản đang cài → mọi user thấy popup 'Cập nhật ngay' mở link. Để trống Phiên bản để tắt.",
                                 "When newer than installed → all users see an 'Update now' popup. Leave version empty to disable."))
                        .font(.caption2)
                }

                Section {
                    Button {
                        Task { await saveGlobal() }
                    } label: {
                        HStack {
                            if gSaving { ProgressView().padding(.trailing, 4) }
                            Text(store.t("Lưu — áp dụng cho MỌI người", "Save — apply to ALL users")).bold()
                        }
                    }
                    .disabled(!gLoaded || gSaving)
                    if !gLoaded {
                        Text(store.t("Đang tải cấu hình toàn cục...", "Loading global config..."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let gMessage {
                        Text(gMessage).font(.footnote).foregroundStyle(gIsError ? .red : .green)
                    }
                } footer: {
                    Text(store.t("Bạn là admin: lời chào, tốc độ và công tắc ở trên là CHUNG cho mọi người dùng. Bấm Lưu để phát cho tất cả khi họ mở app.",
                                 "You are admin: the greeting, speed and toggle above are GLOBAL. Tap Save to apply for everyone."))
                        .font(.caption2)
                }
            }
        }
        .navigationTitle(store.t("Lời chào khi mở app", "Welcome greeting"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            voices = WelcomeVoice.availableVoices
            rateBinding = Double(store.welcomeRate)
            if store.isAdmin { await loadGlobal() }
        }
    }

    // MARK: - Giọng chào toàn cục (admin) — đồng bộ vào giao diện CHUNG ở trên
    private func loadGlobal() async {
        guard let c = try? await store.api.storeConfig() else { return }
        gEnabled = c.welcomeVoiceEnabled ?? true
        if let vt = c.welcomeVoiceText, !vt.isEmpty { gText = vt }
        gRate = Double(c.welcomeVoiceRate ?? 0.5)
        gLogoName = c.logoName; gLogoUrl = c.logoUrl
        gBannerType = c.bannerType; gBannerUrl = c.bannerUrl
        gPopupEnabled = c.welcomePopupEnabled ?? false
        gPopupTitle = c.welcomePopupTitle ?? ""
        gPopupText = c.welcomePopupText ?? ""
        gVersion = c.latestVersion ?? ""
        gUpdateUrl = c.updateUrl ?? ""
        gUpdateMsg = c.updateMessage ?? ""
        // Admin chỉ có 1 lời chào duy nhất → hiển thị giá trị toàn cục lên giao diện chung.
        store.setWelcomeEnabled(gEnabled)
        if !gText.isEmpty { store.setWelcomeText(gText) }
        store.setWelcomeRate(Float(gRate))
        rateBinding = gRate
        gLoaded = true
    }

    private func saveGlobal() async {
        guard gLoaded else { return }
        gSaving = true; gMessage = nil
        defer { gSaving = false }
        // Lấy đúng giá trị đang hiển thị trên giao diện chung.
        gEnabled = store.welcomeEnabled
        gText = store.welcomeText
        gRate = rateBinding
        do {
            let r = try await store.api.adminStoreSetConfig(
                logoName: gLogoName, logoUrl: gLogoUrl,
                bannerType: gBannerType, bannerUrl: gBannerUrl,
                welcomePopupEnabled: gPopupEnabled,
                welcomePopupTitle: gPopupTitle,
                welcomePopupText: gPopupText,
                welcomeVoiceEnabled: gEnabled,
                welcomeVoiceText: gText,
                welcomeVoiceRate: Float(gRate),
                latestVersion: gVersion, updateUrl: gUpdateUrl,
                updateMessage: gUpdateMsg)
            gIsError = false; gMessage = r.message
        } catch {
            gIsError = true; gMessage = error.localizedDescription
        }
    }
}
