import SwiftUI
import AVFoundation

// ============================================================================
//  BỘ CHỌN GIỌNG DÙNG CHUNG — nhúng thẳng vào bất kỳ màn nào (vd "AI xem video")
//  để CHỌN GIỌNG TẠI CHỖ, không cần vào mục "Đọc (TTS)".
//   • Chọn động cơ: Mặc định (iOS) · Chị Google · Siri · ElevenLabs
//   • Giọng iOS/Siri: liệt kê ĐẦY ĐỦ giọng trên máy + tìm kiếm + nghe thử
//   • ElevenLabs: chọn giọng THEO TÊN từ danh sách đầy đủ của máy chủ (không cần chép Voice ID),
//     chọn MODEL (v3 = biểu cảm nhất), chọn TÔNG BIỂU CẢM, tốc độ, biểu cảm tự động
//   • ADMIN: nhập/xoá API key ElevenLabs ngay tại chỗ
// ============================================================================
struct TTSVoicePickerSection: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var tts: TTSEngine

    @State private var expanded = false
    @State private var search = ""
    @State private var onlyVietnamese = true

    // ElevenLabs
    @State private var elevenVoices: [APIClient.ElevenVoice] = []
    @State private var loadingVoices = false
    @State private var voicesError: String?
    @State private var elevenModel = UserDefaults.standard.string(forKey: "eleven_model") ?? "eleven_multilingual_v2"
    @State private var autoEmotion = UserDefaults.standard.bool(forKey: "eleven_auto_emotion")

    // Admin key
    @State private var draftKey = ""
    @State private var keySet = false
    @State private var keyMasked = ""
    @State private var keyBusy = false
    @State private var keyMsg: String?

    private let previewSynth = AVSpeechSynthesizer()

    private static let allVoices: [AVSpeechSynthesisVoice] =
        AVSpeechSynthesisVoice.speechVoices().sorted { $0.name < $1.name }

    private let models: [(id: String, label: String, desc: String)] = [
        ("eleven_v3",              "Eleven v3 ✦ Biểu cảm nhất", "Ngữ điệu & cảm xúc tự nhiên nhất. Cần key/gói hỗ trợ v3."),
        ("eleven_multilingual_v2", "Multilingual v2 ✦ Ổn định", "Đọc tiếng Việt chuẩn, chạy với mọi key."),
        ("eleven_flash_v2_5",      "Flash v2.5 ⚡ Nhanh & rẻ",  "Tốc độ cao, tốn ít credit hơn."),
        ("eleven_turbo_v2_5",      "Turbo v2.5",                "Cân bằng tốc độ và chất lượng."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Giọng đọc", systemImage: "person.wave.2.fill")
                    .font(.headline)
                Spacer()
                Button { withAnimation { expanded.toggle() } } label: {
                    Label(expanded ? "Thu gọn" : "Đổi giọng",
                          systemImage: expanded ? "chevron.up" : "slider.horizontal.3")
                        .font(.caption)
                }.buttonStyle(.bordered)
            }

            // Tóm tắt giọng đang dùng
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                Text(currentSummary).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if expanded {
                Divider()
                enginePicker
                if tts.engineType == .elevenlabs && store.isPro {
                    elevenSection
                } else if tts.engineType == .system || tts.engineType == .siri {
                    deviceVoiceSection
                } else {
                    googleSection
                }
                Divider()
                previewRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(18)
        .task {
            // Bơm thông tin máy chủ để đọc ElevenLabs bằng KEY CHUNG (admin đặt).
            tts.serverBase = store.baseURL
            tts.serverToken = store.token
            if let cfg = try? await store.api.storeConfig() {
                tts.elevenServerKey = (cfg.elevenServerKey ?? false)
            }
            await refreshKeyStatus()
        }
    }

    // ----- Tóm tắt -----
    private var currentSummary: String {
        switch tts.engineType {
        case .elevenlabs:
            let n = tts.elevenVoiceName.isEmpty
                ? (tts.elevenVoiceId.isEmpty ? "chưa chọn" : tts.elevenVoiceId)
                : tts.elevenVoiceName
            let tone = kElevenTonePresets.first { $0.id == tts.elevenToneId }?.label ?? ""
            return "ElevenLabs · \(n)" + (tone.isEmpty ? "" : " · \(tone)")
        case .google:
            return "Chị Google (online)"
        case .siri:
            return "Siri / iOS · " + (voiceName(tts.siriVoiceId) ?? "giọng mặc định")
        case .system:
            return "Mặc định (iOS) · " + (voiceName(tts.voiceId) ?? "giọng mặc định")
        }
    }

    private func voiceName(_ id: String) -> String? {
        guard !id.isEmpty else { return nil }
        return Self.allVoices.first { $0.identifier == id }?.name
    }

    // ----- Chọn động cơ -----
    @ViewBuilder private var enginePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Động cơ giọng").font(.caption).foregroundStyle(.secondary)
            Picker("Động cơ", selection: $tts.engineType) {
                ForEach(TTSEngine.EngineType.allCases.filter { store.isPro || $0 != .elevenlabs }) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !store.isPro {
                Label("Giọng ElevenLabs (AI) chỉ có ở gói PRO.", systemImage: "crown.fill")
                    .font(.caption2).foregroundStyle(Theme.gold)
            }
        }
    }

    // ----- Giọng máy (iOS / Siri): ĐẦY ĐỦ + tìm kiếm -----
    @ViewBuilder private var deviceVoiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $onlyVietnamese) {
                Label("Chỉ hiện giọng tiếng Việt", systemImage: "flag.fill").font(.caption)
            }.tint(Theme.accent)

            TextField("Tìm giọng (tên / ngôn ngữ)…", text: $search)
                .font(.caption).autocorrectionDisabled()
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            let list = filteredVoices
            Text("\(list.count) giọng").font(.caption2).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(list, id: \.identifier) { v in
                        let sel = (tts.engineType == .siri ? tts.siriVoiceId : tts.voiceId) == v.identifier
                        Button {
                            if tts.engineType == .siri { tts.siriVoiceId = v.identifier }
                            else { tts.voiceId = v.identifier }
                            preview(voice: v)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: sel ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(sel ? .green : Theme.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.name).font(.caption.bold())
                                        .foregroundStyle(sel ? .green : .primary)
                                    Text("\(v.language)\(qualityLabel(v))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption2).foregroundStyle(.green)
                            }
                            .padding(.vertical, 6).padding(.horizontal, 8)
                            .background(sel ? Color.green.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)

            styleAndSliders
        }
    }

    private func qualityLabel(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium:  return " · Cao cấp"
        case .enhanced: return " · Nâng cao"
        default:        return ""
        }
    }

    private var filteredVoices: [AVSpeechSynthesisVoice] {
        var a = Self.allVoices
        if onlyVietnamese {
            let vi = a.filter { $0.language.hasPrefix("vi") }
            if !vi.isEmpty { a = vi }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            a = a.filter { $0.name.lowercased().contains(q) || $0.language.lowercased().contains(q) }
        }
        return a
    }

    @ViewBuilder private var googleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chị Google đọc online — không cần chọn giọng máy.")
                .font(.caption2).foregroundStyle(.secondary)
            styleAndSliders
        }
    }

    @ViewBuilder private var styleAndSliders: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kiểu giọng").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kVoiceStyles) { s in
                        let on = (tts.pitch == s.pitch && tts.rate == s.rate)
                        Button { tts.pitch = s.pitch; tts.rate = s.rate } label: {
                            Label(s.label, systemImage: s.icon).font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(on ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
            sliderF("Tốc độ", $tts.rate,
                    AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
            sliderF("Cao độ", $tts.pitch, 0.5...2.0)
            sliderF("Âm lượng", $tts.volume, 0...1)
        }
    }

    // ----- ElevenLabs: giọng đầy đủ + biểu cảm + key admin -----
    @ViewBuilder private var elevenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MODEL (v3 = biểu cảm nhất)
            Text("Model").font(.caption).foregroundStyle(.secondary)
            ForEach(models, id: \.id) { m in
                let on = elevenModel == m.id
                Button {
                    elevenModel = m.id
                    UserDefaults.standard.set(m.id, forKey: "eleven_model")
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: on ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(on ? .green : Theme.accent).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.label).font(.caption.bold()).foregroundStyle(on ? .green : .primary)
                            Text(m.desc).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5).padding(.horizontal, on ? 8 : 0)
                    .background(on ? Color.green.opacity(0.10) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }

            Toggle(isOn: $autoEmotion) {
                Label("Biểu cảm tự động (v3)", systemImage: "theatermasks.fill").font(.caption)
            }
            .tint(Theme.accent)
            .onChange(of: autoEmotion) { v in
                UserDefaults.standard.set(v, forKey: "eleven_auto_emotion")
            }

            Divider()

            // TÔNG BIỂU CẢM
            Text("Tông biểu cảm").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kElevenTonePresets) { tone in
                        let on = tts.elevenToneId == tone.id
                        Button { tts.elevenToneId = tone.id } label: {
                            Label(tone.label, systemImage: tone.icon).font(.caption.bold())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(on ? Color.green.opacity(0.30) : Color(.secondarySystemBackground))
                                .foregroundStyle(on ? .green : .primary)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(on ? Color.green : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 2)
            }

            Divider()

            // DANH SÁCH GIỌNG ĐẦY ĐỦ (chọn theo TÊN — không cần chép Voice ID)
            HStack {
                Text("Chọn giọng (\(elevenVoices.count))").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { Task { await loadVoices() } } label: {
                    if loadingVoices { ProgressView().scaleEffect(0.7) }
                    else { Label("Tải danh sách", systemImage: "arrow.clockwise").font(.caption2) }
                }.buttonStyle(.bordered).disabled(loadingVoices)
            }
            if let voicesError {
                Text("⚠️ " + voicesError).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !elevenVoices.isEmpty {
                TextField("Tìm giọng…", text: $search)
                    .font(.caption).autocorrectionDisabled()
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(filteredEleven, id: \.voiceId) { v in
                            let on = tts.elevenVoiceId == v.voiceId
                            Button {
                                tts.elevenVoiceId = v.voiceId
                                tts.elevenVoiceName = v.name
                                UserDefaults.standard.set(v.name, forKey: "eleven_voice_name")
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: on ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(on ? .green : Theme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(v.name).font(.caption.bold())
                                            .foregroundStyle(on ? .green : .primary)
                                        if !v.desc.isEmpty {
                                            Text(v.desc).font(.caption2).foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6).padding(.horizontal, 8)
                                .background(on ? Color.green.opacity(0.12) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            // Nhập tay Voice ID (vẫn giữ, cho ai có ID riêng)
            Text("Hoặc dán Voice ID").font(.caption2).foregroundStyle(.secondary)
            TextField("Voice ID từ elevenlabs.io", text: $tts.elevenVoiceId)
                .font(.caption).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            sliderD("Tốc độ đọc", $tts.elevenSpeed, 0.5...2.0)
            sliderF("Âm lượng", $tts.volume, 0...1)

            // ADMIN: nhập API key NGAY TẠI CHỖ
            if store.isAdmin {
                Divider()
                adminKeyBox
            } else {
                Text("Giọng ElevenLabs dùng khoá chung do admin cấp — bạn chỉ cần chọn giọng ở trên.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var filteredEleven: [APIClient.ElevenVoice] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return elevenVoices }
        return elevenVoices.filter {
            $0.name.lowercased().contains(q) || $0.desc.lowercased().contains(q)
        }
    }

    @ViewBuilder private var adminKeyBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Admin: API key ElevenLabs (dùng chung)", systemImage: "key.fill")
                .font(.caption.bold()).foregroundStyle(Theme.accent)
            if keySet {
                Text("Đã có khoá trên máy chủ: \(keyMasked)").font(.caption2).foregroundStyle(.green)
            } else {
                Text("Chưa có khoá — khách sẽ không dùng được giọng ElevenLabs.")
                    .font(.caption2).foregroundStyle(.orange)
            }
            SecureField("Dán API key (xi-…)", text: $draftKey)
                .font(.caption).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(8).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Button {
                    Task { await saveKey(draftKey.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } label: {
                    HStack {
                        if keyBusy { ProgressView().scaleEffect(0.7).padding(.trailing, 2) }
                        Label("Lưu khoá", systemImage: "checkmark.circle.fill").font(.caption)
                    }
                }
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(keyBusy || draftKey.trimmingCharacters(in: .whitespaces).isEmpty)

                if keySet {
                    Button { Task { await saveKey("") } } label: {
                        Label("Xoá khoá", systemImage: "trash").font(.caption)
                    }.buttonStyle(.bordered).tint(.red).disabled(keyBusy)
                }
            }
            if let keyMsg {
                Text(keyMsg).font(.caption2)
                    .foregroundStyle(keyMsg.hasPrefix("✓") ? .green : .red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Khoá lưu MÃ HOÁ trên máy chủ, không hiện cho khách. Đặt 1 lần → mọi khách dùng được giọng ElevenLabs.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ----- Nghe thử -----
    @ViewBuilder private var previewRow: some View {
        HStack {
            Button { tts.speak("Xin chào, đây là giọng đọc bạn vừa chọn.") } label: {
                Label("Nghe thử giọng", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.green)
            Button { tts.stop() } label: {
                Label("Dừng", systemImage: "stop.circle.fill")
            }.buttonStyle(.bordered).tint(.red)
        }
    }

    // ----- Helpers -----
    private func preview(voice: AVSpeechSynthesisVoice) {
        previewSynth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: "Xin chào, đây là giọng đọc.")
        u.voice = voice
        u.rate = tts.rate
        u.pitchMultiplier = tts.pitch
        u.volume = tts.volume
        previewSynth.speak(u)
    }

    private func loadVoices() async {
        loadingVoices = true; voicesError = nil
        do { elevenVoices = try await store.api.elevenVoices() }
        catch { voicesError = error.localizedDescription }
        loadingVoices = false
    }

    private func refreshKeyStatus() async {
        guard store.isAdmin else { return }
        if let st = try? await store.api.elevenKeyStatus() {
            keySet = st.set; keyMasked = st.masked
        }
    }

    private func saveKey(_ k: String) async {
        keyBusy = true; keyMsg = nil
        do {
            try await store.api.setElevenServerKey(k)
            draftKey = ""
            keyMsg = k.isEmpty ? "✓ Đã xoá khoá." : "✓ Đã lưu khoá — khách dùng được ngay."
            await refreshKeyStatus()
            if !k.isEmpty { await loadVoices() }
        } catch {
            keyMsg = error.localizedDescription
        }
        keyBusy = false
    }

    @ViewBuilder private func sliderF(_ title: String, _ value: Binding<Float>,
                                      _ range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue))")
                .font(.caption2).foregroundStyle(.secondary)
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }

    @ViewBuilder private func sliderD(_ title: String, _ value: Binding<Double>,
                                      _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(String(format: "%.2f", value.wrappedValue))×")
                .font(.caption2).foregroundStyle(.secondary)
            Slider(value: value, in: range).tint(Theme.accent)
        }
    }
}
