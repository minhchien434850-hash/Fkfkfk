import SwiftUI
import AVFoundation

// ======================== ElevenLabs API Key — Nhập, kiểm tra, lưu Keychain ========================
struct ElevenLabsKeyView: View {
    @EnvironmentObject var store: AppStore
    @Binding var elevenKey: String
    @Binding var elevenVoiceId: String
    @Binding var elevenVoiceName: String

    // Key DÙNG CHUNG trên máy chủ (admin đặt). Khách chỉ nhập Voice ID.
    @State private var serverKeySet = false
    @State private var serverKeyMasked = ""
    @State private var savingServer = false
    @State private var serverMsg: String?
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

            // ----- API key: CHỈ ADMIN nhập; đặt 1 lần → mọi khách dùng chung -----
            if store.isAdmin {
                Section {
                    if serverKeySet {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text("Máy chủ đã có key: \(serverKeyMasked)").font(.caption)
                        }
                    }
                    SecureField("Dán ElevenLabs API key (xi-...)", text: $draftKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    if !draftKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { Task { await saveServerKey() } } label: {
                            HStack {
                                if savingServer { ProgressView().padding(.trailing, 4) }
                                Label("Lưu key lên MÁY CHỦ (dùng chung cho mọi khách)", systemImage: "icloud.and.arrow.up.fill")
                                    .frame(maxWidth: .infinity)
                            }.bold()
                        }.buttonStyle(.borderedProminent).tint(.blue).disabled(savingServer)
                    }
                    if serverKeySet {
                        Button(role: .destructive) { Task { await clearServerKey() } } label: {
                            Label("Xoá key khỏi máy chủ", systemImage: "trash")
                        }
                    }
                    if let serverMsg {
                        Text(serverMsg).font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("API Key (chỉ Admin)") } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Key lưu MÃ HOÁ trên máy chủ, KHÔNG hiện cho khách. Admin đặt 1 lần → mọi khách chỉ cần nhập Voice ID là đọc được.")
                        Link("Lấy API key tại elevenlabs.io →",
                             destination: URL(string: "https://elevenlabs.io/app/speech-synthesis")!)
                            .font(.caption)
                    }
                }
            } else {
                // Khách: không thấy ô key. Chỉ báo trạng thái + nhập Voice ID bên dưới.
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: serverKeySet ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(serverKeySet ? .green : .orange)
                        Text(serverKeySet
                             ? "Giọng ElevenLabs do admin cung cấp — bạn CHỈ cần nhập Voice ID bên dưới."
                             : "Chưa có giọng ElevenLabs (admin chưa cấu hình). Tạm dùng giọng khác.")
                            .font(.caption)
                    }
                } header: { Text("Giọng ElevenLabs") }
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
                    .disabled(!hasAnyKey || elevenVoiceId.isEmpty || testStatus == .loading || testStatus == .playing)

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

            // ----- Xoá key CỤC BỘ (chỉ khi có key riêng trên máy này) -----
            if !elevenKey.isEmpty {
                Section {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Xoá API key trên máy này", systemImage: "trash.fill").frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Cấu hình ElevenLabs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draftVoiceId = elevenVoiceId }
        .task { await loadServerKeyStatus() }
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
    private var hasAnyKey: Bool { !elevenKey.isEmpty || serverKeySet }
    private var statusColor: Color { hasAnyKey ? .green : .orange }
    private var statusIcon: String { hasAnyKey ? "key.fill" : "key.slash.fill" }
    private var statusTitle: String { hasAnyKey ? "Đã sẵn sàng đọc ✓" : "Chưa có API key" }
    private var statusSubtitle: String {
        if !elevenKey.isEmpty { return "Dùng key riêng trên máy này." }
        if serverKeySet { return "Dùng key CHUNG của máy chủ (admin đặt) — chỉ cần Voice ID." }
        return store.isAdmin ? "Admin thêm API key bên dưới để mọi khách dùng chung." : "Admin chưa cấu hình giọng ElevenLabs."
    }

    // ----- Server key (dùng chung) -----
    private func loadServerKeyStatus() async {
        // Trạng thái có key máy chủ (từ store-config, ai cũng đọc được — chỉ true/false).
        if let cfg = try? await store.api.storeConfig() {
            serverKeySet = (cfg.elevenServerKey ?? false)
        }
        // Admin xem thêm phần "che bớt" của key.
        if store.isAdmin, let st = try? await store.api.elevenKeyStatus() {
            serverKeySet = st.set; serverKeyMasked = st.masked
        }
    }
    private func saveServerKey() async {
        let k = draftKey.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return }
        savingServer = true; serverMsg = nil
        do {
            try await store.api.setElevenServerKey(k)
            draftKey = ""
            serverMsg = "Đã lưu key lên máy chủ — mọi khách dùng chung được."
            await loadServerKeyStatus()
        } catch { serverMsg = "Lưu lỗi: \(error.localizedDescription)" }
        savingServer = false
    }
    private func clearServerKey() async {
        savingServer = true; serverMsg = nil
        do {
            try await store.api.setElevenServerKey("")
            serverMsg = "Đã xoá key khỏi máy chủ."
            await loadServerKeyStatus()
        } catch { serverMsg = "Xoá lỗi: \(error.localizedDescription)" }
        savingServer = false
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
        guard !vid.isEmpty, hasAnyKey else { return }
        testStatus = .loading
        testPlayer?.stop(); testPlayer = nil
        Task {
            do {
                let data: Data
                if !key.isEmpty {
                    // Key riêng → gọi thẳng ElevenLabs.
                    guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(vid)") else {
                        testStatus = .failure("Voice ID không hợp lệ"); return
                    }
                    var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 30
                    req.setValue(key, forHTTPHeaderField: "xi-api-key")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
                    let body = elevenLabsRequestBody(text: testSentence, model: selectedModel,
                                                     stability: 0.5, similarityBoost: 0.75,
                                                     style: 0.0, speakerBoost: true)
                    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
                    let (d, resp) = try await URLSession.shared.data(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    if code != 200 {
                        var detail = "HTTP \(code)"
                        if let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                           let msg = (json["detail"] as? [String: Any])?["message"] as? String
                                   ?? json["detail"] as? String { detail = msg }
                        testStatus = .failure(detail); return
                    }
                    data = d
                } else {
                    // Không có key riêng → đọc thử qua MÁY CHỦ (key admin).
                    data = try await store.api.elevenTTS(
                        text: testSentence, voiceId: vid, modelId: selectedModel,
                        stability: 0.5, similarityBoost: 0.75, style: 0.0, speakerBoost: true)
                }
                guard !data.isEmpty else { testStatus = .failure("Không nhận được audio."); return }
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
                testStatus = .failure(error.localizedDescription)
            }
        }
    }
}
