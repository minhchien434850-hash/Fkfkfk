import SwiftUI

// ============================ Zalo Official Account (OA) — chỉ admin ============================
// Kênh Zalo CHÍNH THỐNG: khách quan tâm OA → bot tự chào; khách nhắn → tự trả lời/chuyển admin.
struct ZaloOAView: View {
    @EnvironmentObject var store: AppStore

    @State private var enabled = false
    @State private var appId = ""
    @State private var appSecret = ""
    @State private var hasSecret = false
    @State private var connected = false
    @State private var welcome = "👋 Chào mừng bạn đã quan tâm KENIOS!\nBạn cần hỗ trợ gì cứ nhắn ở đây nhé. 💙"
    @State private var welcomeOn = true
    @State private var autoReply = "Cảm ơn bạn đã nhắn KENIOS! Đội ngũ sẽ phản hồi sớm nhất. 💙"
    @State private var autoReplyOn = false
    @State private var webhookUrl = ""
    @State private var connectUrl = ""

    @State private var saving = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "bubble.left.and.text.bubble.right.fill",
                                title: store.t("Zalo OA", "Zalo OA"),
                                subtitle: store.t("Chào người quan tâm · Tự trả lời tin nhắn",
                                                  "Greet followers · Auto-reply messages"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section {
                    Toggle(store.t("Bật Zalo OA", "Enable Zalo OA"), isOn: $enabled)
                } footer: {
                    Text(store.t("Zalo OA là kênh CHÍNH THỐNG (không lo bị khóa như nick clone). Lưu ý: Zalo KHÔNG cho bot vào nhóm chat thường — OA chỉ chào & trả lời NGƯỜI QUAN TÂM OA.",
                                 "Zalo OA is the OFFICIAL channel. Note: Zalo does NOT allow bots in normal group chats — OA only greets & replies to OA followers."))
                        .font(.caption2)
                }

                // ---- Bước 1: nhập App ID + Secret ----
                Section {
                    TextField("App ID", text: $appId)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation)
                    SecureField(hasSecret ? store.t("Secret Key (đã lưu — nhập để đổi)", "Secret Key (saved — enter to change)") : "Secret Key", text: $appSecret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: {
                    Text(store.t("1. Ứng dụng Zalo", "1. Zalo app"))
                } footer: {
                    Text(store.t("Tạo OA ở oa.zalo.me, tạo Ứng dụng ở developers.zalo.me rồi liên kết với OA. Lấy App ID + Secret Key dán vào đây, bấm Lưu.",
                                 "Create an OA at oa.zalo.me, an app at developers.zalo.me, link them, then paste App ID + Secret Key here and Save."))
                        .font(.caption2)
                }

                // ---- Bước 2: Webhook + Kết nối ----
                if !webhookUrl.isEmpty {
                    Section {
                        HStack {
                            Text("Webhook URL").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = webhookUrl
                                message = store.t("Đã copy Webhook URL", "Webhook URL copied"); isError = false
                            } label: { Image(systemName: "doc.on.doc") }
                        }
                        Text(webhookUrl).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } header: {
                        Text(store.t("2. Dán Webhook vào Zalo", "2. Set Webhook in Zalo"))
                    } footer: {
                        Text(store.t("Vào developers.zalo.me → Ứng dụng → Official Account → Webhook: dán URL trên, bật sự kiện 'follow' và 'user_send_text'.",
                                     "In developers.zalo.me → App → Official Account → Webhook: paste the URL above, enable 'follow' and 'user_send_text' events."))
                            .font(.caption2)
                    }
                }

                if !appId.isEmpty {
                    Section {
                        Link(destination: URL(string: connectUrl.isEmpty ? "https://oa.zalo.me" : connectUrl)!) {
                            Label(connected
                                  ? store.t("Đã kết nối OA ✓ — kết nối lại", "OA connected ✓ — reconnect")
                                  : store.t("Kết nối / Cấp quyền OA", "Connect / Authorize OA"),
                                  systemImage: connected ? "checkmark.seal.fill" : "link")
                                .foregroundStyle(connected ? .green : Theme.accent)
                        }
                    } header: {
                        Text(store.t("3. Cấp quyền", "3. Authorize"))
                    } footer: {
                        Text(store.t("Bấm nút trên → đăng nhập Zalo → cấp quyền cho OA. Xong quay lại đây bấm Tải lại. Token tự gia hạn, không cần làm lại.",
                                     "Tap above → log into Zalo → authorize the OA. Then come back and Reload. Tokens auto-refresh."))
                            .font(.caption2)
                    }
                }

                // ---- Lời chào + tự trả lời ----
                Section {
                    Toggle(store.t("Chào khi có người quan tâm OA", "Greet new OA followers"), isOn: $welcomeOn)
                    if welcomeOn {
                        TextField(store.t("Lời chào", "Welcome text"), text: $welcome, axis: .vertical).lineLimit(2...6)
                    }
                } header: { Text(store.t("👋 Lời chào", "👋 Welcome")) }

                Section {
                    Toggle(store.t("Tự trả lời khi khách nhắn OA", "Auto-reply to messages"), isOn: $autoReplyOn)
                    if autoReplyOn {
                        TextField(store.t("Nội dung tự trả lời", "Auto-reply text"), text: $autoReply, axis: .vertical).lineLimit(2...5)
                    }
                } header: { Text(store.t("💬 Tự trả lời", "💬 Auto-reply")) }
                footer: {
                    Text(store.t("Khi khách nhắn OA, nội dung cũng được chuyển tới admin trên bot Telegram (nếu đã cấu hình) để bạn theo dõi.",
                                 "Incoming OA messages are also forwarded to your Telegram admin (if configured)."))
                        .font(.caption2)
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if saving { ProgressView().padding(.trailing, 4) }
                            Text(store.t("Lưu", "Save")).bold()
                        }
                    }.disabled(saving)
                    Button {
                        Task { await load() }
                    } label: { Label(store.t("Tải lại trạng thái", "Reload status"), systemImage: "arrow.clockwise") }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle(store.t("Zalo OA", "Zalo OA"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let s = try await store.api.adminGetZaloOA()
            enabled = s.enabled
            appId = s.appId ?? ""
            hasSecret = s.hasSecret ?? false
            connected = s.connected ?? false
            if let w = s.welcome, !w.isEmpty { welcome = w }
            welcomeOn = s.welcomeOn ?? true
            if let a = s.autoReply, !a.isEmpty { autoReply = a }
            autoReplyOn = s.autoReplyOn ?? false
            webhookUrl = s.webhookUrl ?? ""
            connectUrl = s.connectUrl ?? ""
        } catch { isError = true; message = error.localizedDescription }
    }

    private func save() async {
        saving = true; message = nil; defer { saving = false }
        var body: [String: Any] = [
            "enabled": enabled, "app_id": appId,
            "welcome": welcome, "welcome_on": welcomeOn,
            "auto_reply": autoReply, "auto_reply_on": autoReplyOn,
        ]
        if !appSecret.isEmpty { body["app_secret"] = appSecret }
        do {
            let s = try await store.api.adminSetZaloOA(body)
            hasSecret = s.hasSecret ?? hasSecret
            connected = s.connected ?? connected
            webhookUrl = s.webhookUrl ?? webhookUrl
            connectUrl = s.connectUrl ?? connectUrl
            appSecret = ""
            isError = false; message = store.t("Đã lưu ✅", "Saved ✅")
        } catch { isError = true; message = error.localizedDescription }
    }
}
