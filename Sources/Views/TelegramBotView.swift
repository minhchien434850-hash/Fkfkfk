import SwiftUI

// ============================ Bot Telegram hỗ trợ (chỉ admin) ============================
struct TelegramBotView: View {
    @EnvironmentObject var store: AppStore

    @State private var token = ""
    @State private var enabled = false
    @State private var adminChat = ""
    @State private var welcome = "👋 Chào mừng bạn đến với hỗ trợ KENIOS!\nBấm nút bên dưới hoặc nhắn nội dung cần hỗ trợ."
    @State private var about = "KENIOS — nền tảng ứng dụng & cửa hàng số."
    @State private var username = ""
    @State private var hasToken = false
    @State private var loaded = false
    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section {
                KHeroHeader(icon: "paperplane.fill",
                            title: store.t("Bot Telegram hỗ trợ", "Telegram support bot"),
                            subtitle: store.t("Khách nhắn bot · Admin trả lời ngay trên Telegram",
                                              "Customers message the bot · Admin replies on Telegram"))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }

            Section {
                Toggle(store.t("Bật bot hỗ trợ", "Enable support bot"), isOn: $enabled)
                if !username.isEmpty {
                    HStack {
                        Text(store.t("Bot", "Bot"))
                        Spacer()
                        Text("@\(username)").foregroundStyle(Theme.accent).textSelection(.enabled)
                    }
                }
            } header: {
                Text(store.t("Trạng thái", "Status"))
            } footer: {
                Text(store.t(hasToken ? "Đã có token. Để trống ô token nếu không muốn đổi." : "Chưa có token — nhập bên dưới.",
                             hasToken ? "Token set. Leave token field blank to keep it." : "No token yet — enter below."))
                    .font(.caption2)
            }

            Section {
                SecureField(store.t("Bot Token (từ @BotFather)", "Bot Token (from @BotFather)"), text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(store.t("Chat ID admin (nhận tin khách)", "Admin Chat ID (receives messages)"), text: $adminChat)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text(store.t("Kết nối", "Connection"))
            } footer: {
                Text(store.t("Chat ID admin: nhắn cho @userinfobot trên Telegram để lấy ID của bạn. Mọi tin khách gửi bot sẽ hiện trong chat này; bạn REPLY vào tin đó để trả lời khách.",
                             "Admin Chat ID: message @userinfobot on Telegram to get your ID. Customer messages appear in this chat; REPLY to a message to answer the customer."))
                    .font(.caption2)
            }

            Section(store.t("Lời chào (/start)", "Welcome (/start)")) {
                TextField(store.t("Lời chào cho khách", "Welcome text"), text: $welcome, axis: .vertical).lineLimit(2...6)
            }
            Section(store.t("Giới thiệu (nút ℹ️)", "About (ℹ️ button)")) {
                TextField(store.t("Giới thiệu ngắn", "Short about"), text: $about, axis: .vertical).lineLimit(2...5)
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack { if saving { ProgressView().padding(.trailing, 4) }
                        Text(store.t("Lưu cấu hình", "Save")).bold() }
                }.disabled(saving)
                Button(store.t("Gửi thử tới admin", "Send test to admin")) {
                    Task { await test() }
                }.disabled(saving || !enabled)
                if let message {
                    Text(message).font(.caption).foregroundStyle(isError ? .red : .green)
                }
            }

            Section(store.t("Hướng dẫn tạo bot", "How to create the bot")) {
                ForEach(Array(guide.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i+1)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 20, height: 20).background(Theme.accent).clipShape(Circle())
                        Text(s).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .navigationTitle(store.t("Bot Telegram", "Telegram bot"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private let guide = [
        "Mở Telegram, nhắn @BotFather → /newbot → đặt tên & username → nhận Bot Token.",
        "Dán Token vào ô trên. Bật công tắc 'Bật bot hỗ trợ'.",
        "Nhắn @userinfobot để lấy Chat ID của bạn, dán vào ô 'Chat ID admin'.",
        "Bấm 'Lưu cấu hình' rồi 'Gửi thử' — nếu nhận được tin trên Telegram là xong.",
        "Khách mở bot, gõ /start, nhắn hỗ trợ → tin hiện trong chat của bạn; Reply để trả lời.",
    ]

    private func load() async {
        guard let s = try? await store.api.adminGetTelegramBot() else { return }
        enabled = s.enabled
        hasToken = s.hasToken ?? false
        adminChat = s.adminChat ?? ""
        if let w = s.welcome, !w.isEmpty { welcome = w }
        if let a = s.about, !a.isEmpty { about = a }
        username = s.username ?? ""
        loaded = true
    }

    private func save() async {
        saving = true; message = nil; defer { saving = false }
        do {
            let s = try await store.api.adminSetTelegramBot(
                token: token, enabled: enabled, adminChat: adminChat, welcome: welcome, about: about)
            token = ""   // đã lưu, xoá khỏi ô
            hasToken = s.hasToken ?? hasToken
            username = s.username ?? username
            isError = (s.tokenOk == false && (s.hasToken ?? false))
            message = isError
                ? store.t("Đã lưu nhưng token không hợp lệ — kiểm tra lại.", "Saved but token invalid — check it.")
                : store.t("Đã lưu ✅" + (username.isEmpty ? "" : " (@\(username))"), "Saved ✅")
        } catch { isError = true; message = error.localizedDescription }
    }

    private func test() async {
        saving = true; message = nil; defer { saving = false }
        do {
            try await store.api.adminTestTelegramBot()
            isError = false
            message = store.t("Đã gửi thử — kiểm tra Telegram của bạn.", "Test sent — check your Telegram.")
        } catch { isError = true; message = error.localizedDescription }
    }
}
