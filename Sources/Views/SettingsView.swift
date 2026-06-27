import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
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

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "gearshape.fill",
                                title: "Cài đặt",
                                subtitle: "Tài khoản · giao diện · dọn dẹp · cache")
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // SERVER — chỉ hiện khi CHƯA cài sẵn máy chủ mặc định (Config.defaultServerURL)
                if Config.defaultServerURL.isEmpty {
                    Section("Kết nối máy chủ (\(store.serverType))") {
                        LabeledContent("URL / IP", value: store.baseURL)
                        HStack {
                            Text("Trạng thái")
                            Spacer()
                            if let connected {
                                Circle().fill(connected ? .green : .red).frame(width: 8, height: 8)
                                Text(connected ? "Đang kết nối" : "Mất kết nối")
                                    .foregroundStyle(connected ? .green : .red)
                            } else { ProgressView() }
                        }
                        Button("Quản lý máy chủ (VPS / Hosting)") { showConnections = true }
                    }
                }

                // ACCOUNT
                Section("Tài khoản") {
                    LabeledContent("Tên đăng nhập", value: store.username ?? "-")
                    HStack {
                        Text("ID của bạn")
                        Spacer()
                        Text(store.publicId.isEmpty ? "—" : store.publicId)
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                    }
                    HStack {
                        Text("Gói")
                        Spacer()
                        Text(store.isPro ? "PRO" : "Free")
                            .foregroundStyle(store.isPro ? .green : .secondary)
                    }
                    HStack {
                        Text("Credits")
                        Spacer()
                        Text("\(store.credits)").foregroundStyle(Theme.accent)
                    }
                    Button("Nạp credits") { showPayment = true }
                    TextField("Gmail", text: $email)
                        .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    TextField("Số điện thoại", text: $phone).keyboardType(.phonePad)
                    SecureField("Đổi mật khẩu (để trống nếu không đổi)", text: $newPassword)
                    Button("Lưu thay đổi") { Task { await saveProfile() } }
                }

                Section(store.t("Ngôn ngữ & Giao diện", "Language & Appearance")) {
                    Picker(store.t("Ngôn ngữ", "Language"), selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) })) {
                        ForEach(kAppLanguages, id: \.0) { code, name in
                            Text(name).tag(code)
                        }
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
                    Text("Áp cho logo/thương hiệu của app (khác với cài đặt cửa hàng).")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ===== Màu chủ đạo =====
                Section("Màu chủ đạo của app") {
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
                Section("Lời chào khi mở app") {
                    NavigationLink {
                        WelcomeGreetingView()
                    } label: {
                        HStack {
                            Label("Lời chào & giọng đọc", systemImage: "waveform.badge.mic")
                            Spacer()
                            Text(store.welcomeEnabled ? "Đang bật" : "Tắt")
                                .font(.caption)
                                .foregroundStyle(store.welcomeEnabled ? .green : .secondary)
                        }
                    }
                }

                // ===== Hiệu ứng logo =====
                Section("Hiệu ứng & Logo") {
                    Toggle("Logo có hiệu ứng động", isOn: Binding(
                        get: { store.logoAnimated },
                        set: { store.setLogoAnimated($0) }))
                    Text("Bật để logo KENIOS và logo cửa hàng có hiệu ứng chuyển động lấp lánh.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // ===== Thông báo =====
                Section("Thông báo") {
                    Button {
                        store.requestNotificationPermission()
                        message = "Đã mở yêu cầu cấp quyền thông báo iOS."
                    } label: {
                        Label("Bật thông báo (sản phẩm mới, cập nhật)",
                              systemImage: "bell.badge")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Mở Cài đặt iOS để quản lý thông báo",
                              systemImage: "gear")
                    }
                    Text("Thông báo xuất hiện khi admin thêm sản phẩm mới hoặc có cập nhật bảo trì.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Dung lượng & Dọn dẹp") {
                    Picker("Xóa tin nhắn cũ hơn", selection: $cleanupDays) {
                        Text("7 ngày").tag(7)
                        Text("30 ngày").tag(30)
                        Text("90 ngày").tag(90)
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
                            Text("Dọn dẹp cơ sở dữ liệu")
                        }
                        .foregroundStyle(.red)
                    }
                    .disabled(cleaning)
                }

                Section("Bộ nhớ đệm (Cache)") {
                    Button {
                        clearCache()
                    } label: { Label("Xoá cache của app", systemImage: "trash") }
                }

                if let message { Text(message).foregroundStyle(.green).font(.footnote) }

                Section {
                    Button("Đăng xuất", role: .destructive) { store.logout() }
                }
            }
            .navigationTitle("Cài đặt")
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
        message = "Đã xoá cache."
    }

    private func saveProfile() async {
        do {
            _ = try await store.api.updateProfile(email: email, phone: phone,
                                                   newPassword: newPassword.isEmpty ? nil : newPassword)
            store.updateLocalUser(email: email, phone: phone)
            newPassword = ""; message = "Đã cập nhật."
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
                Toggle("Bật lời chào tự động khi mở app", isOn: Binding(
                    get: { store.welcomeEnabled },
                    set: { store.setWelcomeEnabled($0) }))
                Text("Khi bật, app sẽ đọc lời chào bằng giọng nói mỗi khi bạn mở app lên.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if store.welcomeEnabled {
                Section("Nội dung lời chào") {
                    TextEditor(text: Binding(
                        get: { store.welcomeText },
                        set: { store.setWelcomeText($0) }))
                        .frame(minHeight: 72)
                }

                Section("Mẫu lời chào (bấm để dùng)") {
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

                Section("Giọng đọc") {
                    Picker("Chọn giọng", selection: Binding(
                        get: { store.welcomeVoiceId },
                        set: { store.setWelcomeVoiceId($0) })) {
                        Text("Chị Google (Online) — như TTS Live").tag("google")
                        Text("Mặc định (vi-VN tự động)").tag("")
                        ForEach(voices, id: \.identifier) { v in
                            Text(WelcomeVoice.displayName(v)).tag(v.identifier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text("Giọng ✦ là giọng Enhanced (rõ, tự nhiên hơn). Cài thêm giọng trong iOS Settings > Accessibility > Spoken Content > Voices.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Tốc độ đọc") {
                    HStack(spacing: 10) {
                        Text("🐢").font(.caption)
                        Slider(value: $rateBinding, in: 0.3...0.65, step: 0.025)
                            .onChange(of: rateBinding) { store.setWelcomeRate(Float($0)) }
                        Text("🐇").font(.caption)
                    }
                    Text("Tốc độ: \(Int(rateBinding * 100))%  ·  (mặc định 50%)")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Thử giọng đọc") {
                    Button {
                        WelcomeVoice.shared.testSpeak(
                            text: store.welcomeText,
                            voiceId: store.welcomeVoiceId,
                            rate: Float(rateBinding))
                    } label: {
                        Label("▶  Phát thử lời chào", systemImage: "play.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button(role: .destructive) {
                        WelcomeVoice.shared.stop()
                    } label: {
                        Label("■  Dừng phát", systemImage: "stop.circle")
                    }
                }
            }
        }
        .navigationTitle("Lời chào khi mở app")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            voices = WelcomeVoice.availableVoices
            rateBinding = Double(store.welcomeRate)
        }
    }
}
