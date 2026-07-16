import SwiftUI
import AVFoundation

// ======================== ElevenLabs API Key — Nhập, kiểm tra, lưu Keychain ========================
struct ElevenLabsKeyView: View {
    @Binding var elevenKey: String
    @Binding var elevenVoiceId: String
    @Binding var elevenVoiceName: String

    @State private var draftKey: String = ""
    @State private var draftVoiceId: String = ""
    @State private var selectedModel: String = UserDefaults.standard.string(forKey: "eleven_model") ?? "eleven_multilingual_v2"
    // v3: tự thêm thẻ cảm xúc theo nội dung bình luận (mặc định BẬT)
    @State private var autoEmotion: Bool = (UserDefaults.standard.object(forKey: "eleven_auto_emotion") as? Bool) ?? true
    @State private var testStatus: TestStatus = .idle
    @State private var testPlayer: AVAudioPlayer?
    @State private var showDeleteConfirm = false
    @State private var isFetchingName = false

    private let testSentence = "Xin chào, đây là giọng ElevenLabs đang được dùng trong ứng dụng."

    let availableModels: [(id: String, label: String, desc: String)] = [
        ("eleven_v3",              "Eleven v3 ✦ Biểu cảm nhất (mới)", "Model mới nhất — ngữ điệu & cảm xúc tự nhiên nhất, gần giống giọng gốc. Cần key/gói hỗ trợ v3."),
        ("eleven_multilingual_v2", "Multilingual v2 ✦ Ổn định",       "Đọc tiếng Việt chuẩn, hỗ trợ 29 ngôn ngữ. Hoạt động với mọi key."),
        ("eleven_flash_v2_5",      "Flash v2.5 ⚡ Nhanh & rẻ",        "Tốc độ cao, tốn ít credit hơn ~3×. Tiếng Việt khá tốt."),
        ("eleven_turbo_v2_5",      "Turbo v2.5",                       "Cân bằng giữa tốc độ và chất lượng."),
    ]

    enum TestStatus: Equatable {
        case idle, loading, playing, success
        case failure(String)
    }

    var body: some View {
        List {
            // ----- Trạng thái key -----
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(statusColor.opacity(0.15)).frame(width: 44, height: 44)
                        Image(systemName: statusIcon).font(.title3).foregroundStyle(statusColor)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle).font(.subheadline.bold())
                        Text(statusSubtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Trạng thái") }

            // ----- Nhập API key -----
            Section {
                SecureField("Dán ElevenLabs API key (xi-...)", text: $draftKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if !draftKey.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { saveKey() } label: {
                        Label("Lưu vào Keychain", systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity).bold()
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                }
            } header: { Text("API Key") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key được lưu trong iOS Keychain — mã hoá phần cứng.")
                    Link("Lấy API key miễn phí tại elevenlabs.io →",
                         destination: URL(string: "https://elevenlabs.io/app/speech-synthesis")!)
                        .font(.caption)
                }
            }

            // ----- Nhập Voice ID -----
            Section {
                TextField("Dán Voice ID từ elevenlabs.io", text: $draftVoiceId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { saveVoiceId() }

                if !elevenVoiceName.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.wave.2.fill").foregroundStyle(.green)
                        Text("Giọng: \(elevenVoiceName)").bold().foregroundStyle(.green)
                    }
                } else if isFetchingName {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Đang lấy tên giọng…").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !draftVoiceId.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button { saveVoiceId() } label: {
                        Label("Lưu Voice ID", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity).bold()
                    }
                    .buttonStyle(.borderedProminent).tint(.indigo)
                }
            } header: { Text("Voice ID") } footer: {
                Text("Vào elevenlabs.io → Voices → chọn giọng → Copy Voice ID → dán vào đây. Tên giọng sẽ tự hiện.")
            }

            // ----- Chọn Model -----
            Section {
                ForEach(availableModels, id: \.id) { m in
                    Button {
                        selectedModel = m.id
                        UserDefaults.standard.set(m.id, forKey: "eleven_model")
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: selectedModel == m.id ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedModel == m.id ? .blue : .secondary)
                                .font(.title3)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.label).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(m.desc).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: { Text("Model") } footer: {
                if selectedModel == "eleven_v3" {
                    Text("Eleven v3: biểu cảm nhất, tự nhận diện ngôn ngữ (tiếng Việt tốt). Chèn THẺ CẢM XÚC ngay trong câu — vd [excited], [whispers], [laughs], [sighs], [sarcastic] — để giọng diễn cảm GIỐNG HỆT bản web. Độ ổn định tự khớp đúng 3 mức Creative/Natural/Robust như web. Cần key có quyền v3.")
                } else {
                    Text("Multilingual v2 cho tiếng Việt tốt nhất. Flash v2.5 nhanh hơn và tốn ít credit hơn.")
                }
            }

            // ----- v3: Tự thêm thẻ cảm xúc theo nội dung -----
            if selectedModel == "eleven_v3" {
                Section {
                    Toggle(isOn: $autoEmotion) {
                        Label("Tự thêm cảm xúc khi đọc", systemImage: "theatermasks.fill")
                    }
                    .tint(.pink)
                    .onChange(of: autoEmotion) { v in
                        UserDefaults.standard.set(v, forKey: "eleven_auto_emotion")
                    }
                } header: { Text("Cảm xúc tự động (v3)") } footer: {
                    Text("Khi BẬT: app đọc nội dung bình luận và chèn 1–3 thẻ cảm xúc hợp ngữ cảnh — càng nhiều dấu !, chữ HOA, emoji, chữ kéo dàiii thì càng nhiều cảm xúc. Cười 😂 → [laughs], hype 🔥 → [excited], dễ thương 🥰 → [warmly], bất ngờ 😱 → [gasps], buồn 😢 → [sad]/[crying], hỏi ? → [curious]… Bình luận TOXIC/khịa sẽ được đọc kiểu cà khịa – coi thường ([sarcastic]/[sighs]) chứ không gắt lại. Nếu bạn TỰ gõ thẻ thì app không chèn thêm.")
                }
            }

            // ----- Phát thử -----
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Câu thử:").font(.caption).foregroundStyle(.secondary)
                    Text("\"\(testSentence)\"").font(.callout).italic()

                    if !elevenVoiceName.isEmpty {
                        Text("Giọng: \(elevenVoiceName) · \(selectedModelLabel)")
                            .font(.caption).foregroundStyle(.blue)
                    }

                    Button { testVoice() } label: {
                        HStack {
                            if testStatus == .loading {
                                ProgressView().progressViewStyle(CircularProgressViewStyle()).padding(.trailing, 4)
                            } else {
                                Image(systemName: testStatus == .playing ? "speaker.wave.3.fill" : "play.circle.fill")
                            }
                            Text(testButtonLabel).bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(testButtonTint)
                    .disabled(activeKey.isEmpty || elevenVoiceId.isEmpty || testStatus == .loading || testStatus == .playing)

                    if case .failure(let msg) = testStatus {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.caption)
                            Text(msg).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: { Text("Kiểm tra giọng") } footer: {
                Text("Yêu cầu đã lưu API key và Voice ID.")
            }

            // ----- Xoá key -----
            if !activeKey.isEmpty {
                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Xoá API key", systemImage: "trash.fill").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình ElevenLabs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftVoiceId = elevenVoiceId
        }
        .confirmationDialog("Xoá API key?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Xoá key ElevenLabs", role: .destructive) { deleteKey() }
            Button("Huỷ", role: .cancel) { }
        } message: {
            Text("App sẽ chuyển về Google TTS khi không có API key.")
        }
    }

    // ----- Helpers -----
    private var activeKey: String {
        let d = draftKey.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? elevenKey : d
    }
    private var selectedModelLabel: String {
        availableModels.first { $0.id == selectedModel }?.label ?? selectedModel
    }
    private var statusColor: Color { elevenKey.isEmpty ? .orange : .green }
    private var statusIcon: String { elevenKey.isEmpty ? "key.slash.fill" : "key.fill" }
    private var statusTitle: String { elevenKey.isEmpty ? "Chưa có API key" : "Đã có API key ✓" }
    private var statusSubtitle: String {
        guard !elevenKey.isEmpty else { return "Nhập API key bên dưới để dùng ElevenLabs." }
        return "Key: \(String(elevenKey.prefix(8)))•••••••• · Lưu trong Keychain"
    }
    private var testButtonLabel: String {
        switch testStatus {
        case .idle:    return "Phát thử"
        case .loading: return "Đang tải…"
        case .playing: return "Đang phát…"
        case .success: return "Phát lại"
        case .failure: return "Thử lại"
        }
    }
    private var testButtonTint: Color {
        if case .failure = testStatus { return .red }
        return .green
    }

    // ----- Actions -----
    private func saveKey() {
        let t = draftKey.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        elevenKey = t
        draftKey = ""
        testStatus = .idle
    }

    private func saveVoiceId() {
        let t = draftVoiceId.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        elevenVoiceId = t  // didSet trong TTSEngine tự fetch tên
        isFetchingName = true
        // Sau 3 giây tắt loading nếu tên đã hiện
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isFetchingName = false }
    }

    private func deleteKey() {
        elevenKey = ""
        draftKey = ""
        testStatus = .idle
        testPlayer?.stop()
        testPlayer = nil
    }

    private func testVoice() {
        let key = activeKey
        let vid = elevenVoiceId.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !vid.isEmpty else { return }
        testStatus = .loading
        testPlayer?.stop()
        testPlayer = nil

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(vid)") else {
            testStatus = .failure("Voice ID không hợp lệ"); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Dùng chung bộ dựng body chuẩn theo model (v3 snap stability 0/0.5/1, bỏ language_code cho v2).
        let body = elevenLabsRequestBody(text: testSentence, model: selectedModel,
                                         stability: 0.5, similarityBoost: 0.75,
                                         style: 0.0, speakerBoost: true)
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                if let error { testStatus = .failure("Lỗi mạng: \(error.localizedDescription)"); return }
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code != 200 {
                    var detail = "HTTP \(code)"
                    if let data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let msg = (json["detail"] as? [String: Any])?["message"] as? String
                               ?? json["detail"] as? String { detail = msg }
                    testStatus = .failure(detail); return
                }
                guard let data, !data.isEmpty else {
                    testStatus = .failure("Không nhận được audio."); return
                }
                do {
                    // .mixWithOthers → phát cùng nhạc app khác, không cắt/không đè âm lượng.
                    try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                    let player = try AVAudioPlayer(data: data)
                    player.prepareToPlay(); player.play()
                    testPlayer = player
                    testStatus = .playing
                    DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.3) {
                        if testStatus == .playing { testStatus = .success }
                    }
                } catch {
                    testStatus = .failure("Không phát được audio: \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
