import SwiftUI

// ============================ Bot Telegram — hỗ trợ + quản lý nhóm (chỉ admin) ============================
struct TelegramBotView: View {
    @EnvironmentObject var store: AppStore

    // Kết nối
    @State private var token = ""
    @State private var enabled = false
    @State private var adminChat = ""
    @State private var welcome = "👋 Chào mừng bạn đến với hỗ trợ KENIOS!\nBấm nút bên dưới hoặc nhắn nội dung cần hỗ trợ."
    @State private var about = "KENIOS — nền tảng ứng dụng & cửa hàng số."
    @State private var username = ""
    @State private var hasToken = false

    // Quản lý nhóm
    @State private var modEnabled = false
    @State private var delLinks = true
    @State private var delStickers = false
    @State private var delPhotos = false
    @State private var warnLimit = 3
    @State private var warnBan = false   // false = mute, true = ban
    @State private var welcomeOn = true
    @State private var welcomeGroup = "👋 Chào mừng {name} đã vào {group}!"
    @State private var welcomeBtnText = ""
    @State private var welcomeBtnUrl = ""
    @State private var goodbyeOn = true
    @State private var goodbye = "👋 Tạm biệt {name}, hẹn gặp lại!"

    // Nâng cao
    @State private var antifloodOn = false
    @State private var antifloodMax = 6
    @State private var cleanService = false
    @State private var captchaOn = false
    @State private var nightmodeOn = false
    @State private var nightStart = 23
    @State private var nightEnd = 6
    @State private var rules = ""
    @State private var blacklist = ""

    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "paperplane.fill",
                            title: store.t("Bot Telegram", "Telegram bot"),
                            subtitle: store.t("Hỗ trợ khách · Quản lý nhóm chuyên nghiệp",
                                              "Customer support · Pro group management"))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            // ---- Kết nối ----
            Section {
                Toggle(store.t("Bật bot", "Enable bot"), isOn: $enabled)
                if !username.isEmpty {
                    HStack { Text("Bot"); Spacer()
                        Text("@\(username)").foregroundStyle(Theme.accent).textSelection(.enabled) }
                }
                SecureField(store.t("Bot Token (từ @BotFather)", "Bot Token (from @BotFather)"), text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(store.t("Chat ID admin", "Admin Chat ID"), text: $adminChat)
                    .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
            } header: {
                Text(store.t("Kết nối", "Connection"))
            } footer: {
                Text(store.t(hasToken ? "Đã có token — để trống nếu không đổi. Chat ID lấy từ @userinfobot."
                                      : "Nhập token từ @BotFather. Chat ID lấy từ @userinfobot.",
                             hasToken ? "Token set — leave blank to keep. Get Chat ID from @userinfobot."
                                      : "Enter token from @BotFather. Get Chat ID from @userinfobot."))
                    .font(.caption2)
            }

            // ---- Quản lý nhóm ----
            Section {
                Toggle(store.t("Bật quản lý nhóm (tự động lọc)", "Enable group moderation"), isOn: $modEnabled)
            } header: {
                Text(store.t("🛡️ Quản lý nhóm", "🛡️ Group moderation"))
            } footer: {
                Text(store.t("Thêm bot vào nhóm và cấp quyền ADMIN (xoá tin, cấm, hạn chế). Trong @BotFather tắt Privacy (/setprivacy → Disable) để bot đọc mọi tin.",
                             "Add the bot to your group as ADMIN (delete, ban, restrict). In @BotFather disable Privacy (/setprivacy → Disable) so it can read all messages."))
                    .font(.caption2)
            }

            if modEnabled {
                Section(store.t("Tự động lọc", "Auto filter")) {
                    Toggle(store.t("Xoá tin có link/spam", "Delete links/spam"), isOn: $delLinks)
                    Toggle(store.t("Xoá sticker & ảnh động", "Delete stickers & GIFs"), isOn: $delStickers)
                    Toggle(store.t("Xoá mọi hình ảnh", "Delete all photos"), isOn: $delPhotos)
                }
                Section {
                    Stepper(store.t("Ngưỡng cảnh báo: ", "Warn limit: ") + "\(warnLimit)", value: $warnLimit, in: 1...10)
                    Picker(store.t("Khi đủ cảnh báo", "On limit reached"), selection: $warnBan) {
                        Text(store.t("Cấm chat (mute)", "Mute")).tag(false)
                        Text(store.t("Cấm khỏi nhóm (ban)", "Ban")).tag(true)
                    }.pickerStyle(.segmented)
                } header: {
                    Text(store.t("Cảnh báo", "Warnings"))
                } footer: {
                    Text(store.t("Vi phạm bị xoá tin + cảnh báo. Đủ ngưỡng thì tự mute/ban. Admin nhóm được bỏ qua.\nLệnh trong nhóm (reply vào người vi phạm): /ban /kick /mute [phút] /unmute /warn /unwarn /id /config",
                                 "Violations are deleted + warned. At the limit, auto mute/ban. Group admins are skipped.\nGroup commands (reply to a user): /ban /kick /mute [min] /unmute /warn /unwarn /id /config"))
                        .font(.caption2)
                }
            }

            // ---- Chào mừng / Tạm biệt ----
            Section {
                Toggle(store.t("Chào mừng thành viên mới", "Welcome new members"), isOn: $welcomeOn)
                if welcomeOn {
                    TextField(store.t("Lời chào (dùng {name}, {group})", "Welcome ({name}, {group})"),
                              text: $welcomeGroup, axis: .vertical).lineLimit(2...5)
                    TextField(store.t("Chữ nút link (tuỳ chọn)", "Link button text (optional)"), text: $welcomeBtnText)
                    TextField("https://... (link nút)", text: $welcomeBtnUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
            } header: {
                Text(store.t("👋 Chào mừng", "👋 Welcome"))
            } footer: {
                Text(store.t("Có thể NHÚNG nút bấm liên kết vào lời chào (điền chữ nút + link). {name} = tên, {group} = tên nhóm.",
                             "You can embed a link button in the welcome (button text + URL). {name}, {group} placeholders."))
                    .font(.caption2)
            }
            Section(store.t("👋 Tạm biệt", "👋 Goodbye")) {
                Toggle(store.t("Chào tạm biệt khi rời nhóm", "Goodbye when a member leaves"), isOn: $goodbyeOn)
                if goodbyeOn {
                    TextField(store.t("Lời tạm biệt (dùng {name})", "Goodbye ({name})"),
                              text: $goodbye, axis: .vertical).lineLimit(2...4)
                }
            }

            // ---- Nâng cao ----
            Section {
                Toggle(store.t("Antiflood (chống gửi dồn dập)", "Antiflood"), isOn: $antifloodOn)
                if antifloodOn {
                    Stepper(store.t("Tối đa ", "Max ") + "\(antifloodMax)" + store.t(" tin/7 giây", " msgs/7s"),
                            value: $antifloodMax, in: 3...30)
                }
                Toggle(store.t("Dọn tin 'đã vào/rời nhóm'", "Clean join/leave messages"), isOn: $cleanService)
                Toggle(store.t("Captcha xác minh thành viên mới", "Captcha verify new members"), isOn: $captchaOn)
                Toggle(store.t("NightMode (khoá nhóm ban đêm)", "NightMode (lock at night)"), isOn: $nightmodeOn)
                if nightmodeOn {
                    Stepper(store.t("Từ ", "From ") + "\(nightStart)h", value: $nightStart, in: 0...23)
                    Stepper(store.t("Đến ", "To ") + "\(nightEnd)h", value: $nightEnd, in: 0...23)
                }
            } header: {
                Text(store.t("⚙️ Nâng cao", "⚙️ Advanced"))
            } footer: {
                Text(store.t("NightMode dùng giờ máy chủ. Còn Khoá (ảnh/video/forward…), Bộ lọc, Ghi chú quản lý bằng LỆNH trong nhóm: /lock /filter /save…",
                             "NightMode uses server time. Locks, Filters and Notes are managed by in-group commands: /lock /filter /save…"))
                    .font(.caption2)
            }
            Section(store.t("Nội quy & Từ cấm", "Rules & Blacklist")) {
                TextField(store.t("Nội quy nhóm (/rules)", "Group rules (/rules)"), text: $rules, axis: .vertical).lineLimit(2...6)
                TextField(store.t("Từ cấm (cách nhau dấu phẩy)", "Banned words (comma-separated)"), text: $blacklist, axis: .vertical).lineLimit(1...4)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            // ---- Hỗ trợ chat riêng ----
            Section(store.t("Hỗ trợ chat riêng", "Private support")) {
                TextField(store.t("Lời chào /start", "Welcome /start"), text: $welcome, axis: .vertical).lineLimit(2...5)
                TextField(store.t("Giới thiệu (nút ℹ️)", "About (ℹ️)"), text: $about, axis: .vertical).lineLimit(2...4)
            }

            // ---- Lưu / Thử ----
            Section {
                Button { Task { await save() } } label: {
                    HStack { if saving { ProgressView().padding(.trailing, 4) }
                        Text(store.t("Lưu cấu hình", "Save")).bold() }
                }.disabled(saving)
                Button(store.t("Gửi thử tới admin", "Send test to admin")) { Task { await test() } }
                    .disabled(saving || !enabled)
                if let message { Text(message).font(.caption).foregroundStyle(isError ? .red : .green) }
            }
        }
        .navigationTitle(store.t("Bot Telegram", "Telegram bot"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let s = try? await store.api.adminGetTelegramBot() else { return }
        enabled = s.enabled; hasToken = s.hasToken ?? false
        adminChat = s.adminChat ?? ""
        if let w = s.welcome, !w.isEmpty { welcome = w }
        if let a = s.about, !a.isEmpty { about = a }
        username = s.username ?? ""
        modEnabled = s.modEnabled ?? false
        delLinks = s.delLinks ?? true
        delStickers = s.delStickers ?? false
        delPhotos = s.delPhotos ?? false
        warnLimit = s.warnLimit ?? 3
        warnBan = (s.warnAction == "ban")
        welcomeOn = s.welcomeOn ?? true
        if let w = s.welcomeGroup, !w.isEmpty { welcomeGroup = w }
        welcomeBtnText = s.welcomeBtnText ?? ""
        welcomeBtnUrl = s.welcomeBtnUrl ?? ""
        goodbyeOn = s.goodbyeOn ?? true
        if let g = s.goodbye, !g.isEmpty { goodbye = g }
        antifloodOn = s.antifloodOn ?? false
        antifloodMax = s.antifloodMax ?? 6
        cleanService = s.cleanService ?? false
        captchaOn = s.captchaOn ?? false
        nightmodeOn = s.nightmodeOn ?? false
        nightStart = s.nightStart ?? 23
        nightEnd = s.nightEnd ?? 6
        rules = s.rules ?? ""
        blacklist = s.blacklist ?? ""
    }

    private func save() async {
        saving = true; message = nil; defer { saving = false }
        var body: [String: Any] = [
            "enabled": enabled, "admin_chat": adminChat, "welcome": welcome, "about": about,
            "mod_enabled": modEnabled, "del_links": delLinks, "del_stickers": delStickers,
            "del_photos": delPhotos, "warn_limit": warnLimit, "warn_action": warnBan ? "ban" : "mute",
            "welcome_on": welcomeOn, "welcome_group": welcomeGroup,
            "welcome_btn_text": welcomeBtnText, "welcome_btn_url": welcomeBtnUrl,
            "goodbye_on": goodbyeOn, "goodbye": goodbye,
            "antiflood_on": antifloodOn, "antiflood_max": antifloodMax,
            "clean_service": cleanService, "captcha_on": captchaOn,
            "nightmode_on": nightmodeOn, "night_start": nightStart, "night_end": nightEnd,
            "rules": rules, "blacklist": blacklist,
        ]
        if !token.isEmpty { body["token"] = token }
        do {
            let s = try await store.api.adminSaveTelegramBot(body)
            token = ""; hasToken = s.hasToken ?? hasToken; username = s.username ?? username
            isError = (s.tokenOk == false && (s.hasToken ?? false))
            message = isError
                ? store.t("Đã lưu nhưng token không hợp lệ.", "Saved but token invalid.")
                : store.t("Đã lưu ✅", "Saved ✅")
        } catch { isError = true; message = error.localizedDescription }
    }

    private func test() async {
        saving = true; message = nil; defer { saving = false }
        do {
            try await store.api.adminTestTelegramBot()
            isError = false; message = store.t("Đã gửi thử — kiểm tra Telegram.", "Test sent — check Telegram.")
        } catch { isError = true; message = error.localizedDescription }
    }
}
