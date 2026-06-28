import SwiftUI

// ============================ Tool nhắn tin tự động (ẩn trong Settings) ============================
// Sử dụng API chính thức của từng nền tảng để gửi tin nhắn tự động
// Telegram: Bot API — cần token bot + chat_id người nhận
// WhatsApp: WhatsApp Business Cloud API — cần Access Token + Phone Number ID
// Zalo: Zalo OA API — cần access_token của OA

private enum AutoPlatform: String, CaseIterable {
    case telegram  = "telegram"
    case whatsapp  = "whatsapp"
    case zalo      = "zalo"

    var label: String {
        switch self {
        case .telegram:  return "Telegram Bot"
        case .whatsapp:  return "WhatsApp Business"
        case .zalo:      return "Zalo OA"
        }
    }
    var icon: String {
        switch self {
        case .telegram:  return "paperplane.fill"
        case .whatsapp:  return "phone.circle.fill"
        case .zalo:      return "message.fill"
        }
    }
    var color: Color {
        switch self {
        case .telegram:  return .blue
        case .whatsapp:  return .green
        case .zalo:      return .cyan
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

    @State private var isRunning   = false
    @State private var currentIdx  = 0
    @State private var countdown   = 0
    @State private var results: [SendResult] = []
    @State private var runTask: Task<Void, Never>?
    @State private var showSetup   = false

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
                    Button {
                        showSetup = true
                    } label: {
                        Label("Hướng dẫn lấy Token / API Key", systemImage: "info.circle")
                            .font(.caption)
                    }
                }

                // Credentials
                Section("Thông tin API") {
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
        !messages.isEmpty && !token.isEmpty && !recipient.isEmpty &&
        (platform != .whatsapp || !phoneNumId.isEmpty)
    }

    @ViewBuilder
    private var validationNote: some View {
        if messages.isEmpty {
            Text("Nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
        } else if token.isEmpty {
            Text("Nhập Token API.").font(.caption2).foregroundStyle(.red)
        } else if platform == .whatsapp && phoneNumId.isEmpty {
            Text("Nhập Phone Number ID.").font(.caption2).foregroundStyle(.red)
        } else if recipient.isEmpty {
            Text("Nhập người nhận.").font(.caption2).foregroundStyle(.red)
        }
    }

    private var recipientHint: String {
        switch platform {
        case .telegram:  return "Chat ID hoặc @username người nhận"
        case .whatsapp:  return "SĐT quốc tế (vd +84901234567)"
        case .zalo:      return "User ID Zalo (lấy từ API)"
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
        scheduleNext(sendNow: true)
    }

    private func stopSession() {
        runTask?.cancel(); runTask = nil
        isRunning = false; countdown = 0
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
                await MainActor.run { isRunning = false; countdown = 0 }
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
        }
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
