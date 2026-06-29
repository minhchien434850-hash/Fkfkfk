import SwiftUI
import AVFoundation
import MediaPlayer

// Mô hình (LiveEventType, VoiceStyle, ElevenTonePreset…) đã tách sang TTSModels.swift.

// ======================== Giao diện ========================
struct TTSView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var tts = TTSEngine()

    @State private var freeText = ""
    @State private var personName = ""
    @State private var content = ""
    @State private var selectedEvent = "gift"
    @State private var search = ""
    private let previewSynth = AVSpeechSynthesizer()

    // ----- Dịch tự động sang tiếng Việt + lọc giọng -----
    @State private var translateToVi = true
    @State private var onlyVietnameseVoices = false

    // ----- TikTok Live: tự động đọc bình luận (như TikFinity) -----
    @State private var tiktokId = ""
    @State private var liveConnected = false
    @State private var liveStatus = ""
    @State private var liveError: String?
    @State private var lastEventId = 0
    @State private var pollTask: Task<Void, Never>?
    @State private var readTypes: Set<String> = ["comment", "gift", "follow", "share", "join"]
    @State private var liveFeed: [TikTokLiveEvent] = []

    // ----- Cấu hình câu phát (greetings) -----
    @State private var templateJoin = UserDefaults.standard.string(forKey: "tts_event_template_join") ?? "Chào mừng {name} đã vào phòng"
    @State private var templateGift = UserDefaults.standard.string(forKey: "tts_event_template_gift") ?? "Cảm ơn {name} đã tặng {content}"
    @State private var templateComment = UserDefaults.standard.string(forKey: "tts_event_template_comment") ?? "{name} bình luận: {content}"
    @State private var templateFollow = UserDefaults.standard.string(forKey: "tts_event_template_follow") ?? "Cảm ơn {name} đã theo dõi"
    @State private var templateShare = UserDefaults.standard.string(forKey: "tts_event_template_share") ?? "Cảm ơn {name} đã chia sẻ live"

    // Cache danh sách giọng 1 lần khi mở app (speechVoices() rất nặng — tránh gọi mỗi lần render gây lag/đứng)
    private static let cachedVoices: [AVSpeechSynthesisVoice] =
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    private static let cachedVietnameseCount: Int =
        cachedVoices.filter { $0.language.hasPrefix("vi") }.count

    private var voices: [AVSpeechSynthesisVoice] {
        var all = Self.cachedVoices
        if onlyVietnameseVoices {
            all = all.filter { $0.language.hasPrefix("vi") }
        }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.language.localizedCaseInsensitiveContains(search)
        }
    }

    private var vietnameseVoiceCount: Int { Self.cachedVietnameseCount }

    // Danh sách giọng cho chế độ Siri: giọng tiếng Việt trước (chất lượng cao xếp đầu),
    // rồi tới các giọng còn lại. Giúp người dùng chọn nhanh giọng "gần Siri" nhất.
    private var siriCandidateVoices: [AVSpeechSynthesisVoice] {
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q { case .premium: return 0; case .enhanced: return 1; default: return 2 }
        }
        let vi = Self.cachedVoices.filter { $0.language.hasPrefix("vi") }
            .sorted { rank($0.quality) < rank($1.quality) }
        let others = Self.cachedVoices.filter { !$0.language.hasPrefix("vi") }
        return vi + others
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    KHeroHeader(icon: "speaker.wave.2.fill",
                                title: store.t("Đọc văn bản", "Read text"),
                                subtitle: store.t("TTS · đọc bình luận TikTok Live · chạy nền",
                                                  "TTS · read TikTok Live comments · background"))

                    // ----- TikTok Live: tự động đọc bình luận -----
                    section("TikTok Live — tự động đọc bình luận") {
                        HStack {
                            Image(systemName: "music.note.tv.fill").foregroundStyle(.pink)
                            textField("ID / @username TikTok hoặc link LIVE", $tiktokId)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // Chọn loại sự kiện sẽ đọc
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(kLiveEvents) { e in
                                    let on = readTypes.contains(e.id)
                                    Button {
                                        if on { readTypes.remove(e.id) } else { readTypes.insert(e.id) }
                                    } label: {
                                        Label(e.label, systemImage: on ? "checkmark.circle.fill" : e.icon)
                                            .font(.caption)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(on ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            if liveConnected {
                                Button(role: .destructive) { disconnectLive() } label: {
                                    Label(store.t("Ngắt kết nối", "Disconnect"), systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)
                            } else {
                                Button { connectLive() } label: {
                                    Label(store.t("Kết nối & đọc", "Connect & read"), systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(tiktokId.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }

                        HStack(spacing: 6) {
                            Circle().fill(liveStatusColor).frame(width: 8, height: 8)
                            Text(liveStatusText).font(.caption).foregroundStyle(.secondary)
                        }
                        if let liveError {
                            Text(liveError).font(.caption2).foregroundStyle(.red)
                        }

                        if !liveFeed.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(liveFeed.suffix(12).reversed()) { ev in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: kLiveEvents.first { $0.id == ev.type }?.icon ?? "text.bubble")
                                            .font(.caption2).foregroundStyle(Theme.accent)
                                        Text(renderLive(ev)).font(.caption2)
                                        Spacer()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Text("Nhập ID người đang LIVE → app tự đọc bình luận/quà bằng giọng đã chọn. Tiếp tục đọc khi khoá màn hình.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    // ----- Cấu hình câu phát (greetings) -----
                    section("Cấu hình câu phát (Greetings & Alerts)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hỗ trợ {name} để chèn tên người và {content} để chèn tên quà/bình luận.")
                                .font(.caption2).foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lời chào người vào phòng (Welcome):").font(.caption).bold()
                                textField("Chào mừng {name} đã vào phòng", $templateJoin)
                                    .onChange(of: templateJoin) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_join")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn tặng quà (Gift):").font(.caption).bold()
                                textField("Cảm ơn {name} đã tặng {content}", $templateGift)
                                    .onChange(of: templateGift) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_gift")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Đọc bình luận (Comment):").font(.caption).bold()
                                textField("{name} bình luận: {content}", $templateComment)
                                    .onChange(of: templateComment) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_comment")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn theo dõi (Follow):").font(.caption).bold()
                                textField("Cảm ơn {name} đã theo dõi", $templateFollow)
                                    .onChange(of: templateFollow) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_follow")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn chia sẻ (Share):").font(.caption).bold()
                                textField("Cảm ơn {name} đã chia sẻ live", $templateShare)
                                    .onChange(of: templateShare) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_share")
                                    }
                            }
                        }
                    }

                    // ----- Thông báo livestream -----
                    section("Thông báo livestream") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(kLiveEvents) { e in
                                    Button { selectedEvent = e.id } label: {
                                        Label(e.label, systemImage: e.icon).font(.caption)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(selectedEvent == e.id ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        textField("Tên người (name)", $personName)
                        if selectedEvent == "gift" || selectedEvent == "comment" {
                            textField(selectedEvent == "gift" ? "Quà (content)" : "Nội dung bình luận", $content)
                        }
                        Button {
                            speakTranslated(renderEvent(), eventType: selectedEvent)
                        } label: {
                            Label(store.t("Đọc thông báo", "Read notice"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text(store.t("Xem trước:", "Preview:") + " \(renderEvent())").font(.caption2).foregroundStyle(.secondary)
                    }

                    // ----- Âm thanh thông báo (quà · follow · share) -----
                    notifSoundSection

                    // ----- Đọc văn bản tự do -----
                    section(store.t("Đọc văn bản (tự dịch sang tiếng Việt)", "Read text (auto-translate to Vietnamese)")) {
                        TextEditor(text: $freeText)
                            .font(.body).frame(minHeight: 110)
                            .padding(6).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { speakTranslated(freeText) } label: {
                            Label(store.t("Đọc", "Read"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // ----- Điều khiển phát -----
                    HStack {
                        Button { tts.pauseOrContinue() } label: {
                            Label(tts.isPaused ? store.t("Tiếp tục", "Resume") : store.t("Tạm dừng", "Pause"),
                                  systemImage: tts.isPaused ? "play.fill" : "pause.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking && !tts.isPaused)
                        Button { tts.skipCurrent() } label: {
                            Label(store.t("Bỏ qua", "Skip"), systemImage: "forward.end.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking)
                        Spacer()
                        Button(role: .destructive) { tts.stop() } label: {
                            Label(store.t("Dừng", "Stop"), systemImage: "stop.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking && !tts.isPaused)
                    }
                    if tts.pendingCount > 0 {
                        Text(store.t("Đang chờ đọc:", "Queued:") + " \(tts.pendingCount) " + store.t("đoạn", "items"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    // ----- Động cơ & Tinh chỉnh giọng -----
                    section(store.t("Thiết lập Động cơ giọng nói", "Voice engine settings")) {
                        Text(store.t("Động cơ", "Engine")).font(.caption).foregroundStyle(.secondary)
                        // Giọng ElevenLabs chỉ dành cho gói PRO — Free không thấy lựa chọn này
                        // Dùng menu (thả xuống) vì có nhiều động cơ, nhãn dài — segmented sẽ bị chật, khó đọc.
                        Picker(store.t("Động cơ", "Engine"), selection: $tts.engineType) {
                            ForEach(TTSEngine.EngineType.allCases.filter { store.isPro || $0 != .elevenlabs }) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                        .onAppear {
                            // Free lỡ đang ở ElevenLabs (từ bản cũ) → đưa về giọng hệ thống
                            if !store.isPro && tts.engineType == .elevenlabs { tts.engineType = .system }
                        }
                        if !store.isPro {
                            Label(store.t("Giọng ElevenLabs (AI) chỉ có ở gói PRO. Nâng cấp để mở khoá.",
                                          "ElevenLabs (AI) voice is PRO-only. Upgrade to unlock."),
                                  systemImage: "crown.fill")
                                .font(.caption2).foregroundStyle(Theme.gold)
                        }

                        Toggle(isOn: $translateToVi) {
                            Label(store.t("Tự dịch sang tiếng Việt khi đọc", "Auto-translate to Vietnamese when reading"), systemImage: "character.bubble")
                                .font(.subheadline)
                        }.tint(Theme.accent)

                        // Bộ lọc tiếng lóng/viết tắt đã tự áp dụng cho mọi giọng (iOS · Siri · Google).
                        // Link mở trình đọc tiếng Việt chuẩn riêng (xem trước văn bản sau khi lọc).
                        NavigationLink {
                            VietnameseSiriTTSView()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "wand.and.stars").foregroundStyle(.green).frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Đọc tiếng Việt chuẩn (lọc tiếng lóng)").font(.subheadline.bold())
                                    Text("Tự đổi 'ko→không', 'đc→được'… rồi đọc bằng giọng vi-VN").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }

                        Text("Kiểu giọng (Chỉ dành cho iOS · Siri · Google — không áp dụng cho ElevenLabs)").font(.caption).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
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

                        slider("Tốc độ", value: $tts.rate,
                               range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                        slider("Cao độ", value: $tts.pitch, range: 0.5...2.0)
                        slider("Âm lượng", value: $tts.volume, range: 0...1)

                        // ElevenLabs — đọc tiếng Việt (chỉ PRO)
                        if tts.engineType == .elevenlabs && store.isPro {
                            Divider().padding(.vertical, 4)

                            // --- Chọn tông giọng ElevenLabs ---
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tông giọng ElevenLabs")
                                    .font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(kElevenTonePresets) { tone in
                                            let on = tts.elevenToneId == tone.id
                                            Button { tts.elevenToneId = tone.id } label: {
                                                Label(tone.label, systemImage: tone.icon)
                                                    .font(.caption.bold())
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .background(on
                                                        ? Color.green.opacity(0.30)
                                                        : Color(.secondarySystemBackground))
                                                    .foregroundStyle(on ? .green : .primary)
                                                    .clipShape(Capsule())
                                                    .overlay(
                                                        Capsule().stroke(on ? Color.green : Color.clear, lineWidth: 1.5)
                                                    )
                                            }.buttonStyle(.plain)
                                        }
                                    }.padding(.vertical, 2)
                                }
                                Text("Chỉ áp dụng khi dùng ElevenLabs API key. Mỗi tông thay đổi cách đọc tiếng Việt (trầm, cảm xúc, rõ ràng…).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }

                            Divider().padding(.vertical, 4)

                            // ---- Nhập Voice ID ----
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Voice ID")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                TextField("Dán Voice ID từ ElevenLabs vào đây", text: $tts.elevenVoiceId)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit { tts.fetchElevenVoiceName(tts.elevenVoiceId) }
                                if !tts.elevenVoiceName.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.wave.2.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                        Text("Giọng: \(tts.elevenVoiceName)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                    }
                                } else if !tts.elevenVoiceId.trimmingCharacters(in: .whitespaces).isEmpty {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("Đang lấy tên giọng…")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Vào elevenlabs.io → Voices → chép Voice ID dán vào đây. Tên giọng sẽ tự hiện sau khi nhập.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }

                            Divider().padding(.vertical, 4)
                            NavigationLink {
                                ElevenLabsKeyView(elevenKey: $tts.elevenKey, elevenVoiceId: $tts.elevenVoiceId, elevenVoiceName: $tts.elevenVoiceName)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: tts.elevenKey.isEmpty
                                          ? "key.slash.fill" : "key.fill")
                                        .foregroundStyle(tts.elevenKey.isEmpty ? .orange : .green)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Cấu hình giọng ElevenLabs")
                                            .font(.subheadline.bold())
                                        Text(tts.elevenKey.isEmpty
                                             ? "Chưa có key — nhấn để thiết lập"
                                             : "✓ API key đã lưu (Keychain)")
                                            .font(.caption2)
                                            .foregroundStyle(tts.elevenKey.isEmpty ? .orange : .green)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    // ----- Chọn giọng (tách thành các view con để trình biên dịch không quá tải) -----
                    if tts.engineType == .system { systemVoiceSection }
                    if tts.engineType == .siri { siriVoiceSection }
                    if tts.engineType == .siriEnVi { siriEnViNoteSection }
                }
                .padding()
            }
            .navigationTitle(store.t("Đọc (TTS)", "Read (TTS)"))
        }
    }

    // ----- Âm thanh thông báo cho 3 sự kiện: tặng quà · follow · chia sẻ -----
    private let notifEventLabels: [(id: String, label: String, icon: String)] = [
        ("gift",   "Tặng quà", "gift.fill"),
        ("follow", "Follow",   "heart.fill"),
        ("share",  "Chia sẻ",  "square.and.arrow.up.fill")
    ]

    @ViewBuilder private var notifSoundSection: some View {
        section("Âm thanh thông báo (như TikFinity) · phát TRƯỚC khi đọc") {
            Text("Hơn 50 âm thanh + ô \"Tùy chỉnh\": dán link mp3 bất kỳ (meme cười, la hét, airhorn…) để dùng âm riêng. CHẠM 1 âm để NGHE THỬ; âm đang chọn có dấu ✓.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(notifEventLabels, id: \.id) { ev in
                soundChipRow(ev.id, label: ev.label, icon: ev.icon)
            }
        }
    }

    // Binding 2 chiều cho link âm thanh tùy chỉnh của 1 sự kiện.
    private func notifUrlBinding(_ type: String) -> Binding<String> {
        Binding(get: { tts.notifSoundUrl(for: type) },
                set: { tts.setNotifSoundUrl($0, for: type) })
    }

    @ViewBuilder private func soundChipRow(_ type: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: icon).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                Spacer()
                // Nghe thử đúng âm đang chọn cho sự kiện này (kể cả link tùy chỉnh)
                Button { tts.previewNotif(for: type) } label: {
                    Label("Nghe thử", systemImage: "play.circle.fill").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(.green)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kNotifSounds) { s in
                        let on = tts.notifSoundId(for: type) == s.id
                        Button {
                            // Chạm = chọn âm; âm tổng hợp thì nghe thử luôn (custom đợi dán link).
                            if s.id != "none" && s.id != "custom" { tts.previewNotifSound(s.id) }
                            tts.setNotifSound(s.id, for: type)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: s.icon).font(.body)
                                Text(s.label).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72, height: 56)
                            .background(on ? Theme.accent.opacity(0.28) : Color(.secondarySystemBackground))
                            .foregroundStyle(on ? Theme.accent : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2).foregroundStyle(.green)
                                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                                        .offset(x: -3, y: 3)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            // Ô dán link khi chọn "Tùy chỉnh" — dùng âm meme tùy ý (mp3).
            if tts.notifSoundId(for: type) == "custom" {
                TextField("Dán link .mp3 (vd meme cười, la hét, airhorn…)", text: notifUrlBinding(type))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.caption)
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.vertical, 4)
    }

    // ----- Chọn giọng hệ thống (iOS mặc định) -----
    @ViewBuilder private var systemVoiceSection: some View {
        section("Giọng đọc hệ thống (\(Self.cachedVoices.count) giọng · \(vietnameseVoiceCount) tiếng Việt)") {
            Toggle(isOn: $onlyVietnameseVoices) {
                Label("Chỉ hiện giọng tiếng Việt", systemImage: "flag.fill").font(.subheadline)
            }.tint(Theme.accent)
            textField("Tìm theo tên / ngôn ngữ (vd: vi, English)", $search)
            VStack(spacing: 0) {
                ForEach(voices, id: \.identifier) { v in
                    voiceRow(v, selected: tts.voiceId == v.identifier) { tts.voiceId = v.identifier }
                }
            }
            Text("Muốn thêm giọng tự nhiên hơn: iOS → Cài đặt → Trợ năng → Nội dung nói → Giọng nói → tải thêm.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ----- Chọn giọng cho chế độ "Giọng Siri (iOS)" -----
    @ViewBuilder private var siriVoiceSection: some View {
        section("Giọng Siri / iOS — chọn giọng có sẵn trên máy bạn") {
            Text("App đã tìm các giọng máy bạn đang có. Chọn 1 giọng (ưu tiên Cao cấp/Nâng cao nghe gần Siri nhất), bấm loa để nghe thử.")
                .font(.caption2).foregroundStyle(.secondary)
            Button { tts.siriVoiceId = "" } label: {
                HStack {
                    Image(systemName: tts.siriVoiceId.isEmpty ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text("Tự động (giọng tốt nhất)").font(.subheadline)
                        Text("App tự chọn giọng chất lượng cao nhất").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }.buttonStyle(.plain).padding(.vertical, 6)
            Divider()
            VStack(spacing: 0) {
                ForEach(siriCandidateVoices, id: \.identifier) { v in
                    voiceRow(v, selected: tts.siriVoiceId == v.identifier, highlightQuality: true) {
                        tts.siriVoiceId = v.identifier
                    }
                }
            }
            Text("Lưu ý: iOS chưa có giọng \"Siri\" riêng cho tiếng Việt — giọng Cao cấp (Linh) là gần Siri nhất. Muốn hay & tự nhiên hơn nữa, hãy dùng \"Chị Google (Online)\".")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ----- Ghi chú cho chế độ Siri Anh·Việt (phiên âm) -----
    @ViewBuilder private var siriEnViNoteSection: some View {
        section("Siri tiếng Anh đọc phiên âm tiếng Việt") {
            Label("Chế độ thử nghiệm", systemImage: "flask.fill")
                .font(.subheadline.bold()).foregroundStyle(.orange)
            Text("App tự đổi chữ tiếng Việt sang cách viết kiểu Anh rồi cho giọng Siri tiếng Anh đọc. Vì giọng Anh KHÔNG có dấu thanh tiếng Việt nên sẽ đọc \"lơ lớ\", không dấu — nghe vui/tham khảo, chưa chuẩn 100%.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Để giọng Anh hay nhất: iOS → Cài đặt → Trợ năng → Nội dung nói → Giọng nói → English → tải giọng Siri / Cao cấp.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // Một hàng giọng: chọn + nghe thử. Tách ra để body nhẹ, biên dịch nhanh.
    @ViewBuilder private func voiceRow(_ v: AVSpeechSynthesisVoice, selected: Bool,
                                       highlightQuality: Bool = false,
                                       onSelect: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading) {
                        Text(v.name).font(.subheadline)
                        Text("\(v.language) · \(qualityText(v.quality))")
                            .font(.caption2)
                            .foregroundStyle(highlightQuality && v.quality != .default ? Color.green : Color.secondary)
                    }
                    Spacer()
                }
            }.buttonStyle(.plain)
            Button {
                let u = AVSpeechUtterance(string: "Xin chào, đây là giọng đọc thử nghiệm.")
                u.voice = v
                u.rate = tts.rate
                u.pitchMultiplier = tts.pitch
                previewSynth.speak(u)
            } label: {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }.padding(.vertical, 6)
        Divider()
    }

    // ----- TikTok Live helpers -----
    private var liveStatusText: String {
        if !liveConnected && liveStatus.isEmpty { return "Chưa kết nối" }
        switch liveStatus {
        case "connecting": return "Đang kết nối tới phòng LIVE..."
        case "connected":  return "Đã kết nối · đang đọc bình luận"
        case "ended":      return "Phiên LIVE đã kết thúc"
        case "error":      return "Lỗi kết nối"
        default:           return liveConnected ? "Đang đọc" : "Chưa kết nối"
        }
    }
    private var liveStatusColor: Color {
        switch liveStatus {
        case "connected": return .green
        case "connecting": return .orange
        case "error", "ended": return .red
        default: return .gray
        }
    }

    private func renderLive(_ ev: TikTokLiveEvent) -> String {
        let template: String
        switch ev.type {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = ev.name.isEmpty ? "bạn" : ev.name
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: ev.content)
            .trimmingCharacters(in: .whitespaces)
    }

    private func connectLive() {
        let id = tiktokId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        liveError = nil; liveFeed = []; lastEventId = 0
        liveStatus = "connecting"; liveConnected = true
        
        tts.startBackgroundMode() // Giữ app chạy ngầm bằng silent audio loop
        
        Task {
            do {
                let s = try await store.api.tiktokLiveConnect(username: id)
                liveStatus = s.status
                startPolling(id)
            } catch {
                liveError = error.localizedDescription
                liveStatus = "error"; liveConnected = false
                tts.stopBackgroundMode()
            }
        }
    }

    private func startPolling(_ id: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let r = try await store.api.tiktokLiveEvents(username: id, after: lastEventId)
                    liveStatus = r.status
                    if let e = r.error { liveError = e }
                    for ev in r.events {
                        liveFeed.append(ev)
                        if readTypes.contains(ev.type) {
                            let text = await liveSpeechText(ev)
                            // Phát âm thanh thông báo (quà/follow/share) TRƯỚC rồi mới đọc.
                            tts.announce(text, eventType: ev.type)
                        }
                    }
                    if liveFeed.count > 120 { liveFeed.removeFirst(liveFeed.count - 120) }
                    lastEventId = r.last
                    if r.status == "ended" || r.status == "error" { break }
                } catch {
                    // bỏ qua lỗi mạng tạm thời, thử lại ở vòng sau
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func disconnectLive() {
        pollTask?.cancel(); pollTask = nil
        liveConnected = false
        liveStatus = ""
        tts.stopBackgroundMode() // Tắt chạy ngầm
        let id = tiktokId.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { try? await store.api.tiktokLiveDisconnect(username: id) }
    }

    /// Dịch nội dung 1 sự kiện live sang tiếng Việt (giữ tên người + mẫu câu Việt), rồi trả về câu để đọc.
    private func liveSpeechText(_ ev: TikTokLiveEvent) async -> String {
        var content = ev.content
        if translateToVi, !content.isEmpty {
            if let tr = try? await store.api.translate(text: content), !tr.text.isEmpty {
                content = tr.text
            }
        }
        let template: String
        switch ev.type {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = ev.name.isEmpty ? "bạn" : ev.name
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: content)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Đọc 1 đoạn text: nếu bật dịch thì dịch sang tiếng Việt trước rồi mới đọc.
    /// Có eventType (gift/follow/share) → phát âm thanh thông báo TRƯỚC khi đọc.
    private func speakTranslated(_ text: String, eventType: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        func read(_ s: String) {
            if let ev = eventType { tts.announce(s, eventType: ev) } else { tts.speak(s) }
        }
        if translateToVi {
            Task {
                if let tr = try? await store.api.translate(text: t), !tr.text.isEmpty {
                    read(tr.text)
                } else {
                    read(t)
                }
            }
        } else {
            read(t)
        }
    }

    // ----- helpers -----
    private func renderEvent() -> String {
        let template: String
        switch selectedEvent {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = personName.isEmpty ? "bạn" : personName
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: content.isEmpty ? "" : content)
            .trimmingCharacters(in: .whitespaces)
    }
    private func qualityText(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .enhanced: return "nâng cao"
        case .premium:  return "cao cấp"
        default:        return "thường"
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
        .padding(12)
        .kCard(12)
    }
    private func textField(_ ph: String, _ text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .padding(8).background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func slider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.caption2).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}

