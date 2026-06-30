import SwiftUI
import UIKit

// ============================ Tool nhắn tin tự động (ẩn trong Settings) ============================
// Sử dụng API chính thức của từng nền tảng để gửi tin nhắn tự động
// Telegram: Bot API — cần token bot + chat_id người nhận
// WhatsApp: WhatsApp Business Cloud API — cần Access Token + Phone Number ID
// Zalo: Zalo OA API — cần access_token của OA

private enum AutoPlatform: String, CaseIterable {
    case telegram  = "telegram"
    case whatsapp  = "whatsapp"
    case zalo      = "zalo"
    case webhook   = "webhook"

    var label: String {
        switch self {
        case .telegram:  return "Telegram Bot"
        case .whatsapp:  return "WhatsApp Business"
        case .zalo:      return "Zalo OA"
        case .webhook:   return "Webhook / API riêng"
        }
    }
    var icon: String {
        switch self {
        case .telegram:  return "paperplane.fill"
        case .whatsapp:  return "phone.circle.fill"
        case .zalo:      return "message.fill"
        case .webhook:   return "link"
        }
    }
    var color: Color {
        switch self {
        case .telegram:  return .blue
        case .whatsapp:  return .green
        case .zalo:      return .cyan
        case .webhook:   return .orange
        }
    }
    var setupHint: String {
        switch self {
        case .telegram:
            return "1. Mở @BotFather trên Telegram\n2. Gõ /newbot → lấy Bot Token\n3. Chat thử với bot, rồi mở: https://api.telegram.org/bot<TOKEN>/getUpdates để lấy chat_id"
        case .whatsapp:
            return "1. Tạo tài khoản tại developers.facebook.com\n2. Tạo app → WhatsApp → lấy Access Token & Phone Number ID\n3. Recipient là số điện thoại quốc tế (vd +84901234567)"
        case .zalo:
            return "1. Tạo Zalo Official Account tại oa.zalo.me\n2. Vào Cài đặt → API → lấy Access Token\n3. Recipient là user_id (lấy từ API get_profile)"
        case .webhook:
            return "Gửi tin tới BẤT KỲ dịch vụ nào có webhook/API HTTP (Discord, Slack, n8n, hoặc API backend riêng trên VPS của bạn).\n1. Dán URL webhook vào ô \"Webhook URL\".\n2. Mẫu JSON: dùng {text} cho nội dung tin, {recipient} cho người nhận.\nVí dụ Discord: {\"content\":\"{text}\"}\nVí dụ riêng: {\"to\":\"{recipient}\",\"message\":\"{text}\"}"
        }
    }
}

private struct SendResult: Identifiable {
    let id = UUID()
    let index: Int
    let text: String
    var status: Status = .pending
    var error: String?
    enum Status { case pending, sending, ok, fail }
}

struct AutoMessengerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @AppStorage("amPlatform")     private var platformRaw = "telegram"
    @AppStorage("amRawText")      private var rawText = ""
    @AppStorage("amRecipient")    private var recipient = ""
    @AppStorage("amDelaySec")     private var delaySec = 10
    @AppStorage("amToken")        private var token = ""
    @AppStorage("amPhoneNumId")   private var phoneNumId = ""  // WhatsApp only
    @AppStorage("amWebhookURL")   private var webhookURL = ""  // Webhook only
    @AppStorage("amWebhookBody")  private var webhookBody = "{\"content\":\"{text}\"}"  // Webhook JSON mẫu

    @State private var isRunning   = false
    @State private var currentIdx  = 0
    @State private var countdown   = 0
    @State private var results: [SendResult] = []
    @State private var runTask: Task<Void, Never>?
    @State private var showSetup   = false
    @State private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    private var platform: AutoPlatform { AutoPlatform(rawValue: platformRaw) ?? .telegram }

    private var messages: [String] {
        rawText.components(separatedBy: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "bolt.horizontal.fill",
                                title: "Nhắn tin tự động",
                                subtitle: "Gửi thẳng qua API — không cần mở app")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Platform
                Section("Nền tảng") {
                    Picker("Nền tảng", selection: $platformRaw) {
                        ForEach(AutoPlatform.allCases, id: \.rawValue) { p in
                            Label(p.label, systemImage: p.icon).tag(p.rawValue)
                        }
                    }
                    .disabled(isRunning)
                    Button {
                        showSetup = true
                    } label: {
                        Label("Hướng dẫn lấy Token / API Key", systemImage: "info.circle")
                            .font(.caption)
                    }
                }

                // Credentials
                Section("Thông tin API") {
                    if platform == .webhook {
                        TextField("Webhook URL (https://...)", text: $webhookURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Mẫu JSON gửi đi (dùng {text} và {recipient})").font(.caption2).foregroundStyle(.secondary)
                            TextEditor(text: $webhookBody)
                                .frame(minHeight: 60)
                                .font(.system(.caption, design: .monospaced))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        TextField("Người nhận (tuỳ chọn — cho {recipient})", text: $recipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField(platform == .telegram ? "Bot Token (vd 123456:ABC...)" : "Access Token", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if platform == .whatsapp {
                            TextField("Phone Number ID (từ Meta dashboard)", text: $phoneNumId)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        TextField(recipientHint, text: $recipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(platform == .telegram ? .default : .phonePad)
                    }
                }
                .disabled(isRunning)

                // Delay
                Section {
                    Stepper(value: $delaySec, in: 3...300) {
                        HStack {
                            Text("Giãn cách mỗi tin")
                            Spacer()
                            Text("\(delaySec) giây")
                                .foregroundStyle(store.accentColor)
                                .font(.subheadline.bold())
                        }
                    }
                } footer: {
                    Text("Mỗi \(delaySec)s sẽ tự động gửi tin tiếp theo qua \(platform.label).")
                        .font(.caption2)
                }

                // Messages
                Section {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 110)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isRunning)
                } header: {
                    HStack {
                        Text("Danh sách tin (dùng : để phân cách)")
                        Spacer()
                        Text("\(messages.count) tin")
                            .font(.caption.bold())
                            .foregroundStyle(store.accentColor)
                    }
                } footer: {
                    Text("Ví dụ: Ê bạn ơi:Trả lời đi:Sao im lặng thế 😄")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Results / progress
                if !results.isEmpty {
                    Section("Kết quả gửi") {
                        ForEach(results) { r in
                            HStack(spacing: 8) {
                                resultIcon(r.status)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.text).font(.caption).lineLimit(2)
                                    if let e = r.error {
                                        Text(e).font(.caption2).foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                                if r.status == .sending {
                                    ProgressView().scaleEffect(0.7)
                                }
                            }
                        }
                    }
                }

                // Countdown while running
                if isRunning {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().stroke(Color(.systemFill), lineWidth: 5)
                                        .frame(width: 64, height: 64)
                                    Circle()
                                        .trim(from: 0, to: countdown > 0 ? CGFloat(countdown) / CGFloat(delaySec) : 0)
                                        .stroke(store.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                        .frame(width: 64, height: 64)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 1), value: countdown)
                                    Text("\(countdown)")
                                        .font(.title3.monospacedDigit().bold())
                                }
                                Text("Tin \(currentIdx + 1) / \(messages.count)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                // Start / Stop
                Section {
                    if isRunning {
                        Button(role: .destructive) { stopSession() } label: {
                            Label("■  Dừng gửi", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    } else {
                        Button { startSession() } label: {
                            Label("▶  Bắt đầu gửi tự động", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(canStart ? store.accentColor : Color.gray)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canStart)
                        if !canStart { validationNote }
                    }
                }
            }
            .navigationTitle("Tự động nhắn tin 🤖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onDisappear { stopSession() }
            .sheet(isPresented: $showSetup) { setupGuide }
        }
    }

    @ViewBuilder
    private func resultIcon(_ status: SendResult.Status) -> some View {
        switch status {
        case .pending: Image(systemName: "clock").foregroundStyle(.secondary)
        case .sending: Image(systemName: "arrow.up.circle").foregroundStyle(.orange)
        case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .fail:    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    private var canStart: Bool {
        if messages.isEmpty { return false }
        if platform == .webhook {
            return !webhookURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !token.isEmpty && !recipient.isEmpty &&
            (platform != .whatsapp || !phoneNumId.isEmpty)
    }

    @ViewBuilder
    private var validationNote: some View {
        if messages.isEmpty {
            Text("Nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
        } else if platform == .webhook && webhookURL.trimmingCharacters(in: .whitespaces).isEmpty {
            Text("Nhập Webhook URL.").font(.caption2).foregroundStyle(.red)
        } else if platform != .webhook && token.isEmpty {
            Text("Nhập Token API.").font(.caption2).foregroundStyle(.red)
        } else if platform == .whatsapp && phoneNumId.isEmpty {
            Text("Nhập Phone Number ID.").font(.caption2).foregroundStyle(.red)
        } else if platform != .webhook && recipient.isEmpty {
            Text("Nhập người nhận.").font(.caption2).foregroundStyle(.red)
        }
    }

    private var recipientHint: String {
        switch platform {
        case .telegram:  return "Chat ID hoặc @username người nhận"
        case .whatsapp:  return "SĐT quốc tế (vd +84901234567)"
        case .zalo:      return "User ID Zalo (lấy từ API)"
        case .webhook:   return "Người nhận (tuỳ chọn)"
        }
    }

    @ViewBuilder
    private var setupGuide: some View {
        NavigationStack {
            Form {
                ForEach(AutoPlatform.allCases, id: \.rawValue) { p in
                    Section(p.label) {
                        Text(p.setupHint)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Cách lấy API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { showSetup = false } } }
        }
    }

    // MARK: - Session

    private func startSession() {
        guard canStart else { return }
        results = messages.enumerated().map { SendResult(index: $0.offset, text: $0.element) }
        currentIdx = 0
        isRunning = true
        beginBackground()
        scheduleNext(sendNow: true)
    }

    private func stopSession() {
        runTask?.cancel(); runTask = nil
        isRunning = false; countdown = 0
        endBackground()
    }

    // Xin thêm thời gian chạy ngầm để vòng lặp gửi (qua API) không bị iOS đóng băng
    // ngay khi ẩn app / khoá màn hình. iOS chỉ cho thêm vài chục giây — không phải 24/7.
    private func beginBackground() {
        endBackground()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "KeniosAutoMessaging") {
            // Hết thời gian ngầm cho phép → dừng an toàn để khỏi bị hệ thống kill.
            stopSession()
        }
    }

    private func endBackground() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }

    private func scheduleNext(sendNow: Bool) {
        runTask?.cancel()
        runTask = Task {
            if sendNow {
                guard !Task.isCancelled else { return }
                await sendCurrent()
            }
            // countdown to next
            guard currentIdx + 1 < messages.count else {
                await MainActor.run { isRunning = false; countdown = 0; endBackground() }
                return
            }
            for i in stride(from: delaySec, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run { countdown = i }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { currentIdx += 1 }
            scheduleNext(sendNow: true)
        }
    }

    private func sendCurrent() async {
        let idx = currentIdx
        guard idx < messages.count else { return }
        let text = messages[idx]
        await MainActor.run { results[idx].status = .sending }
        do {
            try await sendMessage(text: text)
            await MainActor.run { results[idx].status = .ok }
        } catch {
            await MainActor.run {
                results[idx].status = .fail
                results[idx].error = error.localizedDescription
            }
        }
    }

    private func sendMessage(text: String) async throws {
        switch platform {
        case .telegram:  try await sendTelegram(text: text)
        case .whatsapp:  try await sendWhatsApp(text: text)
        case .zalo:      try await sendZalo(text: text)
        case .webhook:   try await sendWebhook(text: text)
        }
    }

    // MARK: - Webhook / API riêng (Discord, Slack, n8n, backend VPS...)
    private func sendWebhook(text: String) async throws {
        let urlStr = webhookURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: urlStr) else {
            throw NSError(domain: "Webhook", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Webhook URL không hợp lệ."])
        }
        // Chèn nội dung vào mẫu JSON một cách an toàn (escape ký tự đặc biệt của JSON).
        let safeText = jsonEscaped(text)
        let safeRecipient = jsonEscaped(recipient.trimmingCharacters(in: .whitespaces))
        var payload = webhookBody.isEmpty ? "{\"text\":\"{text}\"}" : webhookBody
        payload = payload
            .replacingOccurrences(of: "{text}", with: safeText)
            .replacingOccurrences(of: "{recipient}", with: safeRecipient)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = payload.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Webhook", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(raw.prefix(160))"])
        }
    }

    /// Escape chuỗi để nhúng an toàn vào giá trị JSON (giữ dấu ", \\, xuống dòng…).
    private func jsonEscaped(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:   out.append(ch)
            }
        }
        return out
    }

    // MARK: - Telegram Bot API
    private func sendTelegram(text: String) async throws {
        let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["chat_id": recipient.trimmingCharacters(in: .whitespaces), "text": text]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            let msg = (try? JSONDecoder().decode(TGError.self, from: data))?.description ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Telegram", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    // MARK: - WhatsApp Business Cloud API
    private func sendWhatsApp(text: String) async throws {
        let phone = recipient.filter { $0.isNumber }
        let url = URL(string: "https://graph.facebook.com/v18.0/\(phoneNumId)/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "messaging_product": "whatsapp",
            "to": phone,
            "type": "text",
            "text": ["body": text]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "WhatsApp", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
        }
    }

    // MARK: - Zalo OA API
    private func sendZalo(text: String) async throws {
        let url = URL(string: "https://openapi.zalo.me/v3.0/oa/message/cs")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(token, forHTTPHeaderField: "access_token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "recipient": ["user_id": recipient.trimmingCharacters(in: .whitespaces)],
            "message": ["text": text]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let raw = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "Zalo", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: raw])
        }
    }
}

private struct TGError: Decodable {
    let description: String
}
