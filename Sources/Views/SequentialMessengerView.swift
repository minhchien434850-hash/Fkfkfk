import SwiftUI

// ============================ Tool nhắn tin tuần tự (ẩn trong Settings) ============================
// Mỗi X giây: copy tin tiếp theo vào clipboard + mở app nhắn tin (bạn chỉ cần paste → Gửi)

private struct MsgPlatform: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let urlScheme: (String, String) -> String   // (recipient, encodedText) -> urlString
}

private let kMsgPlatforms: [MsgPlatform] = [
    .init(id: "telegram", label: "Telegram",  icon: "paperplane.fill",       color: .blue) { rec, _ in
        let user = rec.hasPrefix("@") ? String(rec.dropFirst()) : rec
        return "tg://resolve?domain=\(user)"
    },
    .init(id: "zalo",     label: "Zalo",      icon: "message.fill",           color: .cyan) { _, _ in
        "zalo://"
    },
    .init(id: "whatsapp", label: "WhatsApp",  icon: "phone.circle.fill",      color: .green) { rec, txt in
        let phone = rec.filter { $0.isNumber || $0 == "+" }
        return "whatsapp://send?phone=\(phone)&text=\(txt)"
    },
    .init(id: "messenger",label: "Messenger", icon: "ellipsis.message.fill",  color: .purple) { _, _ in
        "fb-messenger://"
    },
    .init(id: "imessage", label: "iMessage",  icon: "bubble.left.fill",       color: Color(red: 0.1, green: 0.75, blue: 0.1)) { rec, txt in
        "sms:\(rec)&body=\(txt)"
    },
    .init(id: "viber",    label: "Viber",     icon: "phone.fill",             color: .indigo) { rec, _ in
        "viber://chat?number=\(rec.filter { $0.isNumber || $0 == "+" })"
    },
]

struct SequentialMessengerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @AppStorage("smRawText")        private var rawText = ""
    @AppStorage("smPlatform")       private var platformId = "telegram"
    @AppStorage("smRecipient")      private var recipient = ""
    @AppStorage("smDelaySec")       private var delaySec = 10

    @State private var isRunning    = false
    @State private var currentIdx   = 0
    @State private var countdown    = 0
    @State private var copiedMsg    = ""
    @State private var runTask: Task<Void, Never>?

    // Phân tích danh sách tin nhắn (phân cách bằng ":")
    private var messages: [String] {
        rawText.components(separatedBy: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var currentPlatform: MsgPlatform {
        kMsgPlatforms.first { $0.id == platformId } ?? kMsgPlatforms[0]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "bubble.left.and.bubble.right.fill",
                                title: "Tin nhắn tuần tự",
                                subtitle: "Copy & mở app — paste → Gửi là xong")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Nền tảng + người nhận
                Section("Ứng dụng nhắn tin") {
                    Picker("Ứng dụng", selection: $platformId) {
                        ForEach(kMsgPlatforms) { p in
                            Label(p.label, systemImage: p.icon).tag(p.id)
                        }
                    }
                    TextField(recipientHint, text: $recipient)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(platformId == "telegram" ? .default : .phonePad)
                }

                // Thời gian chờ
                Section {
                    Stepper(value: $delaySec, in: 3...120) {
                        HStack {
                            Text("Khoảng cách mỗi tin")
                            Spacer()
                            Text("\(delaySec) giây")
                                .foregroundStyle(store.accentColor)
                                .font(.subheadline.bold())
                        }
                    }
                } footer: {
                    Text("Sau mỗi \(delaySec)s: app tự copy tin tiếp theo + mở \(currentPlatform.label). Bạn paste & Gửi trong \(currentPlatform.label) rồi quay lại.")
                        .font(.caption2)
                }

                // Soạn tin nhắn
                Section {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 130)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Danh sách tin (dùng : để xuống dòng)")
                        Spacer()
                        Text("\(messages.count) tin")
                            .font(.caption.bold())
                            .foregroundStyle(store.accentColor)
                    }
                } footer: {
                    Text("Ví dụ: Ê bạn ơi:Trả lời đi bạn:Tui đây này:Sao im lặng thế 😄")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Preview danh sách
                if !messages.isEmpty {
                    Section("Xem trước \(messages.count) tin nhắn") {
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, msg in
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isRunning && i == currentIdx
                                              ? store.accentColor : Color(.tertiarySystemBackground))
                                        .frame(width: 24, height: 24)
                                    Text("\(i + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(isRunning && i == currentIdx ? .white : .secondary)
                                }
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(isRunning && i < currentIdx ? .secondary : .primary)
                                    .strikethrough(isRunning && i < currentIdx)
                                Spacer()
                                if isRunning && i == currentIdx {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }

                // Trạng thái đang chạy
                if isRunning {
                    Section {
                        VStack(spacing: 14) {
                            // Đếm ngược
                            ZStack {
                                Circle()
                                    .stroke(Color(.systemFill), lineWidth: 6)
                                    .frame(width: 80, height: 80)
                                Circle()
                                    .trim(from: 0, to: countdown > 0 ? CGFloat(countdown) / CGFloat(delaySec) : 0)
                                    .stroke(store.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                    .frame(width: 80, height: 80)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 1), value: countdown)
                                VStack(spacing: 2) {
                                    Text("\(countdown)")
                                        .font(.title2.monospacedDigit().bold())
                                    Text("giây").font(.caption2).foregroundStyle(.secondary)
                                }
                            }

                            Text("Tin \(currentIdx + 1)/\(messages.count)")
                                .font(.caption.bold()).foregroundStyle(.secondary)

                            if !copiedMsg.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Đã copy vào clipboard:", systemImage: "doc.on.clipboard.fill")
                                        .font(.caption.bold()).foregroundStyle(.green)
                                    Text(copiedMsg)
                                        .font(.subheadline)
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }

                            // Mở app ngay (không chờ đếm ngược)
                            Button {
                                openCurrentInApp()
                            } label: {
                                HStack {
                                    Image(systemName: currentPlatform.icon)
                                    Text("Mở \(currentPlatform.label) ngay")
                                }
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(currentPlatform.color)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }

                // Nút Bắt đầu / Dừng
                Section {
                    if isRunning {
                        Button(role: .destructive) { stopSession() } label: {
                            Label("■  Dừng gửi", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.red)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { startSession() } label: {
                            Label("▶  Bắt đầu gửi", systemImage: "play.circle.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(messages.isEmpty || recipient.isEmpty ? Color.gray : store.accentColor)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(messages.isEmpty || recipient.isEmpty)

                        if messages.isEmpty {
                            Text("Vui lòng nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
                        } else if recipient.isEmpty {
                            Text("Vui lòng nhập username/SĐT người nhận.").font(.caption2).foregroundStyle(.red)
                        }
                    }
                }

                Section("Hướng dẫn") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Nhập các tin nhắn, phân cách bằng dấu :", systemImage: "1.circle.fill")
                        Label("Chọn app nhắn tin và nhập người nhận", systemImage: "2.circle.fill")
                        Label("Đặt số giây giữa mỗi tin nhắn", systemImage: "3.circle.fill")
                        Label("Bấm Bắt đầu → app copy tin & mở \(currentPlatform.label)", systemImage: "4.circle.fill")
                        Label("Paste (giữ ô chat → Dán) rồi bấm Gửi → quay lại KENIOS", systemImage: "5.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Tin nhắn vui 🎭")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onDisappear { stopSession() }
        }
    }

    // MARK: - Helpers

    private var recipientHint: String {
        switch platformId {
        case "telegram":                   return "@username (vd @tenbạn)"
        case "zalo", "imessage", "viber": return "Số điện thoại (vd 0901234567)"
        case "whatsapp":                   return "SĐT quốc tế (vd +84901234567)"
        case "messenger":                  return "Link profile (tự mở app)"
        default:                           return "Username hoặc số điện thoại"
        }
    }

    // MARK: - Session control

    private func startSession() {
        guard !messages.isEmpty, !recipient.isEmpty else { return }
        currentIdx = 0
        isRunning = true
        copyAndOpen(messages[0])
        scheduleNext()
    }

    private func stopSession() {
        runTask?.cancel(); runTask = nil
        isRunning = false; countdown = 0; copiedMsg = ""
    }

    private func openCurrentInApp() {
        guard currentIdx < messages.count else { return }
        openInApp(messages[currentIdx])
    }

    private func copyAndOpen(_ text: String) {
        UIPasteboard.general.string = text
        copiedMsg = text
        openInApp(text)
    }

    private func openInApp(_ text: String) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlStr = currentPlatform.urlScheme(recipient.trimmingCharacters(in: .whitespaces), encoded)
        if let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        }
    }

    private func scheduleNext() {
        runTask?.cancel()
        runTask = Task {
            for i in stride(from: delaySec, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run { countdown = i }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                currentIdx += 1
                if currentIdx < messages.count {
                    copyAndOpen(messages[currentIdx])
                    scheduleNext()
                } else {
                    stopSession()
                }
            }
        }
    }
}
