import SwiftUI
import AVFoundation
import MediaPlayer

// ======================== Engine TTS (đọc văn bản, phát nền) ========================
final class TTSEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    enum EngineType: String, CaseIterable, Identifiable {
        case system = "system"
        case google = "google"
        case siri = "siri"
        case siriEnVi = "siri_en_vi"
        case elevenlabs = "elevenlabs"

        var id: String { self.rawValue }
        var label: String {
            switch self {
            case .system: return "Mặc định (iOS)"
            case .google: return "Chị Google (Online)"
            case .siri: return "Giọng Siri (iOS)"
            case .siriEnVi: return "Siri Anh·Việt (phiên âm)"
            case .elevenlabs: return "Giọng ElevenLabs"
            }
        }
    }

    private let synth = AVSpeechSynthesizer()
    private var silentPlayer: AVAudioPlayer?
    private var notifPlayer: AVAudioPlayer?   // phát âm thanh thông báo (follow/quà/share…) TRƯỚC khi đọc
    
    // Google TTS Queue
    private var googleQueue: [String] = []
    private var googleAudio: AVAudioPlayer?      // phát từ Data đã tải sẵn (mượt, không khoảng lặng)
    private var googleNextData: Data?            // PREFETCH: audio của đoạn KẾ đã tải sẵn trong lúc đọc đoạn này
    private var isPlayingGoogle = false
    private var googleItemToken = 0   // chống "kẹt" 1 đoạn: watchdog so khớp token

    // Tốc độ phát cho Google (map thanh rate → bội số 0.5x…2.0x; mặc định rate 0.5 = 1.0x)
    private var googleSpeed: Float { max(0.5, min(2.0, rate * 2.0)) }

    // ElevenLabs (đa ngôn ngữ — đọc tiếng Việt)
    // Key lưu trong Keychain (mã hoá iOS) — KHÔNG dùng UserDefaults cho secret.
    @Published var elevenKey: String = Keychain.load("elevenlabs_api_key") ?? "" {
        didSet {
            let trimmed = elevenKey.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                Keychain.delete("elevenlabs_api_key")
            } else {
                Keychain.save("elevenlabs_api_key", trimmed)
            }
        }
    }
    // Voice ID của ElevenLabs — nhập từ tài khoản elevenlabs.io của bạn.
    @Published var elevenVoiceId: String = UserDefaults.standard.string(forKey: "eleven_voice_id") ?? "" {
        didSet {
            UserDefaults.standard.set(elevenVoiceId, forKey: "eleven_voice_id")
            let vid = elevenVoiceId.trimmingCharacters(in: .whitespaces)
            if vid.isEmpty {
                elevenVoiceName = ""
                UserDefaults.standard.removeObject(forKey: "eleven_voice_name")
            } else {
                fetchElevenVoiceName(vid)
            }
        }
    }
    // Tên giọng hiển thị — tự động lấy từ API khi nhập Voice ID
    @Published var elevenVoiceName: String = UserDefaults.standard.string(forKey: "eleven_voice_name") ?? ""

    func fetchElevenVoiceName(_ vid: String) {
        let key = elevenKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, let url = URL(string: "https://api.elevenlabs.io/v1/voices/\(vid)") else { return }
        var req = URLRequest(url: url)
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self, let data else { return }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = obj["name"] as? String {
                DispatchQueue.main.async {
                    self.elevenVoiceName = name
                    UserDefaults.standard.set(name, forKey: "eleven_voice_name")
                }
            }
        }.resume()
    }
    // Preset tông giọng TikTok đang chọn (mặc định: TikTok Nhẹ)
    @Published var elevenToneId: String = UserDefaults.standard.string(forKey: "eleven_tone_id") ?? "tiktok_calm" {
        didSet { UserDefaults.standard.set(elevenToneId, forKey: "eleven_tone_id") }
    }
    private var currentTone: ElevenTonePreset {
        kElevenTonePresets.first { $0.id == elevenToneId } ?? kElevenTonePresets[0]
    }
    private var elevenPlayer: AVAudioPlayer?
    private var elevenQueue: [String] = []
    private var isPlayingEleven = false

    @Published var isSpeaking = false
    @Published var isPaused = false

    @Published var voiceId: String = ""          // identifier của AVSpeechSynthesisVoice
    // Giọng riêng cho chế độ "Giọng Siri (iOS)" — người dùng tự chọn trong app, app nhớ lại.
    @Published var siriVoiceId: String = UserDefaults.standard.string(forKey: "tts_siri_voice_id") ?? "" {
        didSet { UserDefaults.standard.set(siriVoiceId, forKey: "tts_siri_voice_id") }
    }
    @Published var rate: Float = UserDefaults.standard.object(forKey: "tts_rate") as? Float ?? AVSpeechUtteranceDefaultSpeechRate {
        didSet {
            UserDefaults.standard.set(rate, forKey: "tts_rate")
            // Đổi tốc độ NGAY cho Google đang phát (không cần đợi đoạn mới)
            googleAudio?.enableRate = true
            googleAudio?.rate = googleSpeed
        }
    }
    @Published var pitch: Float = UserDefaults.standard.object(forKey: "tts_pitch") as? Float ?? 1.0 {
        didSet { UserDefaults.standard.set(pitch, forKey: "tts_pitch") }
    }
    @Published var volume: Float = UserDefaults.standard.object(forKey: "tts_volume") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "tts_volume")
            // Cập nhật âm lượng ngay cho audio đang phát (Google / ElevenLabs), không cần đợi đọc câu mới.
            googleAudio?.volume = volume
            elevenPlayer?.volume = volume
        }
    }
    // Số đoạn còn đang chờ đọc trong hàng đợi (Google/ElevenLabs) — hiện ra UI để biết app có bị "ứ" bình luận không.
    @Published var pendingCount: Int = 0
    // Giới hạn hàng đợi khi live quá đông bình luận → bỏ bớt đoạn cũ, ưu tiên đọc đoạn mới gần thời điểm hiện tại.
    var maxQueueSize: Int = 20
    
    @Published var engineType: EngineType = .system {
        didSet {
            UserDefaults.standard.set(engineType.rawValue, forKey: "tts_engine_type")
        }
    }

    override init() {
        super.init()
        synth.delegate = self
        // chọn mặc định 1 giọng tiếng Việt nếu có
        if let vi = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("vi") }) {
            voiceId = vi.identifier
        } else if let any = AVSpeechSynthesisVoice.speechVoices().first {
            voiceId = any.identifier
        }
        
        if let savedEngine = UserDefaults.standard.string(forKey: "tts_engine_type"),
           let type = EngineType(rawValue: savedEngine) {
            self.engineType = type
        }
        setupRemoteCommands()   // điều khiển từ Control Center / màn khoá
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioInterruption),
                                                name: AVAudioSession.interruptionNotification, object: nil)
    }

    /// Tự khôi phục đọc/phát nền sau khi cuộc gọi đến/đi hoặc Siri… làm gián đoạn audio session.
    @objc private func handleAudioInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        if type == .ended {
            activateSession()
            if silentPlayer != nil { startBackgroundMode() }
            if isPlayingEleven, !isPaused { elevenPlayer?.play() }
            if isPlayingGoogle, !isPaused { googleAudio?.play() }
        }
    }

    /// Bật phiên audio dạng playback để tiếp tục đọc khi khoá màn hình / chuyển app khác.
    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? s.setActive(true, options: [])
    }

    func speak(_ text: String) {
        // Lọc & chuẩn hóa văn bản tiếng Việt (mở rộng viết tắt/tiếng lóng, làm sạch ký tự)
        // cho giọng iOS mặc định · Siri · Chị Google.
        // ElevenLabs GIỮ NGUYÊN văn bản gốc (không lọc) theo yêu cầu.
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = engineType == .elevenlabs ? raw : VietnameseTextNormalizer.normalize(raw)
        guard !t.isEmpty else { return }
        activateSession()
        // Tự bật chế độ nền (giữ audio sống khi chuyển app / khoá màn hình)
        if silentPlayer == nil { startBackgroundMode() }
        updateNowPlaying(playing: true)   // hiện ở Control Center / màn khoá

        switch engineType {
        case .google:
            playGoogleTTS(t)
        case .siri:
            playSiriTTS(t)
        case .siriEnVi:
            playSiriEnViTTS(t)
        case .elevenlabs:
            playElevenLabsTTS(t)
        case .system:
            playSystemTTS(t)
        }
    }

    // ===== Âm thanh thông báo (chỉ cho: tặng quà · follow · chia sẻ) =====
    // Loại sự kiện có gắn âm thanh thông báo (đúng 3 cái người dùng yêu cầu).
    static let notifEventTypes = ["gift", "follow", "share"]

    // Âm mặc định cho từng loại (người dùng đổi được trong cài đặt).
    private func defaultNotifSound(for type: String) -> String {
        switch type {
        case "gift":   return "coin"
        case "follow": return "heart"
        case "share":  return "chime"
        default:       return "none"
        }
    }

    func notifSoundId(for type: String) -> String {
        UserDefaults.standard.string(forKey: "tts_sound_\(type)") ?? defaultNotifSound(for: type)
    }
    func setNotifSound(_ id: String, for type: String) {
        UserDefaults.standard.set(id, forKey: "tts_sound_\(type)")
        objectWillChange.send()
    }

    /// Phát âm thanh thông báo cho loại sự kiện rồi GỌI `then` (đọc text). Nếu không có âm → đọc ngay.
    private func playNotif(for type: String, then: @escaping () -> Void) {
        let sid = notifSoundId(for: type)
        guard let preset = kNotifSounds.first(where: { $0.id == sid }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else {
            then(); return
        }
        activateSession()
        do {
            let p = try AVAudioPlayer(data: data)
            p.volume = volume
            p.prepareToPlay()
            let dur = p.duration
            p.play()
            notifPlayer = p
            // Đọc NGAY SAU khi âm thanh phát xong (đúng yêu cầu: âm trước, đọc sau).
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.05) { then() }
        } catch {
            then()
        }
    }

    /// Nghe thử 1 âm thanh (dùng cho màn chọn âm).
    func previewNotifSound(_ id: String) {
        guard let preset = kNotifSounds.first(where: { $0.id == id }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else { return }
        activateSession()
        if let p = try? AVAudioPlayer(data: data) {
            p.volume = volume
            p.prepareToPlay()
            p.play()
            notifPlayer = p
        }
    }

    /// Thông báo 1 sự kiện: phát âm thanh (nếu là gift/follow/share) TRƯỚC rồi mới đọc.
    func announce(_ text: String, eventType: String) {
        activateSession()
        if silentPlayer == nil { startBackgroundMode() }
        if Self.notifEventTypes.contains(eventType) {
            playNotif(for: eventType) { [weak self] in self?.speak(text) }
        } else {
            speak(text)
        }
    }

    private func playSystemTTS(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        if let v = AVSpeechSynthesisVoice(identifier: voiceId) { u.voice = v }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)          // tự xếp hàng nếu đang đọc cái khác
    }
    
    private func playSiriTTS(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        // Ưu tiên giọng người dùng tự chọn trong app; nếu chưa chọn thì tự lấy giọng tốt nhất.
        if !siriVoiceId.isEmpty, let v = AVSpeechSynthesisVoice(identifier: siriVoiceId) {
            u.voice = v
        } else if let v = bestSiriVoice() {
            u.voice = v
        }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)
    }

    // Chọn ĐÚNG giọng Siri: ưu tiên giọng Siri tiếng Việt thật, rồi tới giọng tiếng Việt
    // CHẤT LƯỢNG CAO nhất (premium > enhanced) — KHÔNG lấy giọng "compact" thường (nghe khác hẳn Siri).
    private func bestSiriVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        func q(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality {
            case .premium:  return 3
            case .enhanced: return 2
            default:        return 1
            }
        }
        let isSiri: (AVSpeechSynthesisVoice) -> Bool = { $0.identifier.lowercased().contains("siri") }
        // 1) Giọng Siri tiếng Việt thật (chất lượng cao nhất).
        if let v = voices.filter({ $0.language.hasPrefix("vi") && isSiri($0) }).max(by: { q($0) < q($1) }) {
            return v
        }
        // 2) Chưa cài giọng Siri tiếng Việt → chọn giọng tiếng Việt CHẤT LƯỢNG CAO nhất (gần Siri nhất, đúng tiếng).
        if let v = voices.filter({ $0.language.hasPrefix("vi") }).max(by: { q($0) < q($1) }) {
            return v
        }
        // 3) Không có giọng tiếng Việt → bất kỳ giọng Siri thật nào.
        if let v = voices.filter(isSiri).max(by: { q($0) < q($1) }) { return v }
        return voices.first
    }

    // ===== Siri tiếng Anh đọc phiên âm tiếng Việt (CHẾ ĐỘ RIÊNG, không đụng giọng khác) =====
    // Lưu ý: giọng Anh không có dấu thanh tiếng Việt → đọc "lơ lớ", chỉ mang tính thử nghiệm.
    private func playSiriEnViTTS(_ text: String) {
        let phonetic = Self.vietnameseToEnglishPhonetic(text)
        let u = AVSpeechUtterance(string: phonetic)
        if let v = bestEnglishVoice() { u.voice = v }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)
    }

    // Chọn giọng tiếng Anh tốt nhất (ưu tiên Siri en, rồi premium/enhanced).
    private func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        func q(_ v: AVSpeechSynthesisVoice) -> Int {
            switch v.quality { case .premium: return 3; case .enhanced: return 2; default: return 1 }
        }
        let isSiri: (AVSpeechSynthesisVoice) -> Bool = { $0.identifier.lowercased().contains("siri") }
        if let v = voices.filter({ $0.language.hasPrefix("en") && isSiri($0) }).max(by: { q($0) < q($1) }) { return v }
        if let v = voices.filter({ $0.language.hasPrefix("en") }).max(by: { q($0) < q($1) }) { return v }
        return voices.first
    }

    // Bỏ dấu thanh (sắc/huyền/hỏi/ngã/nặng) NHƯNG GIỮ chất nguyên âm (ă â ê ô ơ ư) và đ.
    private static func detoneKeepVowelQuality(_ s: String) -> String {
        let toneScalars: Set<UInt32> = [0x300, 0x301, 0x303, 0x309, 0x323] // huyền, sắc, ngã, hỏi, nặng
        let decomposed = s.decomposedStringWithCanonicalMapping
        var view = String.UnicodeScalarView()
        for u in decomposed.unicodeScalars where !toneScalars.contains(u.value) { view.append(u) }
        return String(view).precomposedStringWithCanonicalMapping
    }

    // Phiên âm tiếng Việt → cách viết kiểu Anh để giọng Siri tiếng Anh đọc gần giống.
    // Quét 1 lượt trái→phải, ưu tiên cụm dài nhất, KHÔNG đọc lại kết quả (tránh hỏng âm).
    static func vietnameseToEnglishPhonetic(_ text: String) -> String {
        let base = Array(detoneKeepVowelQuality(text).lowercased())
        // Thứ tự QUAN TRỌNG: cụm dài / phụ âm ghép đứng trước nguyên âm đơn.
        let map: [(String, String)] = [
            ("ngh", "ng"),
            ("ươ", "uh"), ("uô", "wo"), ("iê", "ye"), ("yê", "ye"),
            ("ng", "ng"), ("nh", "ny"), ("ph", "f"), ("th", "t"), ("kh", "k"),
            ("gh", "g"), ("tr", "tr"), ("ch", "ch"), ("gi", "y"), ("qu", "kw"),
            ("â", "uh"), ("ă", "ah"), ("ê", "ay"), ("ô", "oh"), ("ơ", "uh"), ("ư", "oo"), ("đ", "d"),
            ("a", "ah"), ("e", "eh"), ("i", "ee"), ("o", "aw"), ("u", "oo"), ("y", "ee"),
            ("d", "z"), ("c", "k"), ("k", "k"), ("q", "k"), ("x", "s")
        ]
        let patterns = map.map { (Array($0.0), $0.1) }
        var out = ""
        var i = 0
        while i < base.count {
            var matched = false
            for (pat, rep) in patterns {
                if i + pat.count <= base.count, Array(base[i..<i+pat.count]) == pat {
                    out += rep
                    i += pat.count
                    matched = true
                    break
                }
            }
            if !matched { out.append(base[i]); i += 1 }
        }
        return out
    }

    private func playElevenLabsTTS(_ text: String) {
        // Dùng ElevenLabs chỉ khi có cả API key VÀ Voice ID
        let key = elevenKey.trimmingCharacters(in: .whitespaces)
        let vid = elevenVoiceId.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty && !vid.isEmpty {
            playElevenLabs(text)
            return
        }
        // Chưa nhập Voice ID → fallback Google TTS
        playGoogleTTS(text)
    }

    // Hàm dự phòng: đọc bằng giọng Việt trên thiết bị khi Google TTS không khả dụng
    private func playElevenLabsOfflineFallback(_ text: String) {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let viVoices = voices.filter { $0.language.hasPrefix("vi") }
        let viVoice = viVoices.first { $0.quality == .premium }
            ?? viVoices.first { $0.quality == .enhanced }
            ?? viVoices.first { $0.name.lowercased().contains("nam") }
            ?? viVoices.first
        guard let v = viVoice else { return } // không có giọng Việt, bỏ qua
        let u = AVSpeechUtterance(string: text)
        u.voice = v
        u.rate = min(rate, 0.52)               // Tốc độ vừa phải
        u.pitchMultiplier = min(pitch, 0.80)   // pitch trầm tự nhiên
        u.volume = volume
        u.preUtteranceDelay = 0.05             // giảm delay đầu câu
        synth.speak(u)
    }
    
    private func playGoogleTTS(_ text: String) {
        // Google TTS giới hạn ~200 ký tự/yêu cầu → chia 180 và đọc lần lượt TOÀN BỘ.
        let chunks = splitTextIntoChunks(text, maxLen: 180)
        for chunk in chunks {
            googleQueue.append(chunk)
        }
        // Khi live quá đông bình luận, hàng đợi có thể phình to khiến TTS đọc trễ rất lâu so với thực tế.
        // Giữ lại các đoạn MỚI NHẤT, bỏ bớt đoạn cũ để app luôn "đuổi kịp" livestream.
        if googleQueue.count > maxQueueSize {
            googleQueue.removeFirst(googleQueue.count - maxQueueSize)
        }
        pendingCount = googleQueue.count + elevenQueue.count
        if !isPlayingGoogle {
            playNextGoogleItem()
        }
    }
    
    // Chia đoạn THÔNG MINH: GIỮ trọn câu (tách theo . ? ! ; xuống dòng) rồi GỘP các câu
    // lại tới gần maxLen. Ít đoạn hơn → ít khoảng lặng giữa các đoạn → đọc mượt, rõ hơn.
    private func splitTextIntoChunks(_ text: String, maxLen: Int) -> [String] {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        // Tách thành các câu trọn vẹn (giữ lại dấu kết câu).
        var sentences: [String] = []
        var cur = ""
        for ch in flat {
            cur.append(ch)
            if ".?!;".contains(ch) {
                let s = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        // Gộp câu tới maxLen; câu nào quá dài thì cắt theo từ.
        var chunks: [String] = []
        var buf = ""
        func flush() { if !buf.isEmpty { chunks.append(buf); buf = "" } }
        for s in sentences {
            if s.count > maxLen {
                flush()
                var line = ""
                for word in s.components(separatedBy: .whitespaces) where !word.isEmpty {
                    let cand = line.isEmpty ? word : line + " " + word
                    if cand.count <= maxLen { line = cand }
                    else { if !line.isEmpty { chunks.append(line) }; line = word }
                }
                if !line.isEmpty { chunks.append(line) }
            } else if (buf.count + 1 + s.count) <= maxLen {
                buf = buf.isEmpty ? s : buf + " " + s
            } else {
                flush(); buf = s
            }
        }
        flush()
        return chunks
    }
    
    // Tải audio 1 đoạn từ Google (TRẢ VỀ Data hoàn chỉnh) — phát bằng AVAudioPlayer nên KHÔNG
    // có khoảng lặng do streaming. Có User-Agent giống trình duyệt thật để Google không chặn.
    private func fetchGoogle(_ text: String, completion: @escaping (Data?) -> Void) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=tw-ob&q=\(encoded)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // Audio rỗng/bị chặn thường rất nhỏ → coi như thất bại.
            if let data, code == 200, data.count > 200 {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    // PREFETCH: tải sẵn audio của đoạn KẾ TIẾP trong lúc đoạn hiện tại đang đọc → hết khoảng lặng.
    private func prefetchNextGoogle() {
        guard googleNextData == nil, let next = googleQueue.first else { return }
        fetchGoogle(next) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                // Chỉ giữ nếu đoạn này vẫn là đoạn đầu hàng đợi (chưa bị bỏ do live đông).
                if self.googleQueue.first == next { self.googleNextData = data }
            }
        }
    }

    private func playNextGoogleItem() {
        guard !googleQueue.isEmpty else {
            isPlayingGoogle = false
            isSpeaking = false
            googleNextData = nil
            pendingCount = elevenQueue.count
            updateNowPlaying(playing: false)
            return
        }

        isPlayingGoogle = true
        isSpeaking = true
        googleItemToken += 1
        let token = googleItemToken
        let text = googleQueue.removeFirst()
        pendingCount = googleQueue.count + elevenQueue.count

        // Nếu đã prefetch sẵn đoạn này → phát NGAY (không đợi mạng = không có khoảng lặng).
        if let data = googleNextData {
            googleNextData = nil
            playGoogleData(data, token: token, retryText: text)
        } else {
            // Chưa kịp prefetch → tải đoạn này rồi phát.
            fetchGoogle(text) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, self.googleItemToken == token, self.isPlayingGoogle else { return }
                    if let data {
                        self.playGoogleData(data, token: token, retryText: nil)
                    } else {
                        // Google chặn/timeout đoạn này → bỏ qua, đọc tiếp ngay (không đứng im).
                        self.playNextGoogleItem()
                    }
                }
            }
        }
    }

    // Phát audio đã tải xong bằng AVAudioPlayer (mượt, chỉnh tốc độ giữ cao độ).
    private func playGoogleData(_ data: Data, token: Int, retryText: String?) {
        do {
            activateSession()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = googleSpeed
            player.volume = volume
            player.prepareToPlay()
            player.play()
            googleAudio = player
            updateNowPlaying(playing: true)
            // Ngay khi bắt đầu phát đoạn này → tải sẵn đoạn KẾ (prefetch) để liền mạch.
            prefetchNextGoogle()
        } catch {
            // Data hỏng → bỏ đoạn, đọc tiếp.
            if self.googleItemToken == token { playNextGoogleItem() }
        }
    }

    // ===== ElevenLabs (đa ngôn ngữ · đọc tiếng Việt) =====
    private func playElevenLabs(_ text: String) {
        elevenQueue.append(text)
        if elevenQueue.count > maxQueueSize {
            elevenQueue.removeFirst(elevenQueue.count - maxQueueSize)
        }
        pendingCount = googleQueue.count + elevenQueue.count
        if !isPlayingEleven { playNextEleven() }
    }

    private func playNextEleven() {
        guard !elevenQueue.isEmpty else {
            isPlayingEleven = false
            isSpeaking = false
            pendingCount = googleQueue.count
            updateNowPlaying(playing: false)
            return
        }
        isPlayingEleven = true
        isSpeaking = true
        updateNowPlaying(playing: true)
        let text = elevenQueue.removeFirst()
        pendingCount = googleQueue.count + elevenQueue.count
        let key = elevenKey.trimmingCharacters(in: .whitespaces)
        let vid = elevenVoiceId.trimmingCharacters(in: .whitespaces)
        guard !vid.isEmpty, let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(vid)") else {
            playNextEleven(); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "xi-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        // Dùng model do người dùng chọn trong ElevenLabsKeyView (lưu UserDefaults)
        let model = UserDefaults.standard.string(forKey: "eleven_model") ?? "eleven_multilingual_v2"
        let tone = currentTone
        let body: [String: Any] = [
            "text": text,
            "model_id": model,
            "language_code": "vi",
            "voice_settings": [
                "stability": tone.stability,
                "similarity_boost": tone.similarityBoost,
                "style": tone.style,
                "use_speaker_boost": tone.speakerBoost
            ]
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if let data, code == 200, !data.isEmpty {
                    do {
                        self.activateSession()
                        let player = try AVAudioPlayer(data: data)
                        player.delegate = self
                        player.volume = self.volume
                        player.prepareToPlay()
                        player.play()
                        self.elevenPlayer = player
                    } catch {
                        self.playNextEleven()
                    }
                } else {
                    // Lỗi key/mạng → bỏ đoạn này, đọc tiếp phần còn lại
                    self.playNextEleven()
                }
            }
        }.resume()
    }

    // ===== Now Playing (hiện ở Control Center / màn khoá) =====
    func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil); c.pauseCommand.removeTarget(nil); c.stopCommand.removeTarget(nil)
        c.playCommand.isEnabled = true; c.pauseCommand.isEnabled = true; c.stopCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in self?.pauseOrContinue(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pauseOrContinue(); return .success }
        c.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
    }

    private func updateNowPlaying(playing: Bool) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = "KENIOS đang đọc"
        info[MPMediaItemPropertyArtist] = "KENIOS AI"
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        googleQueue.removeAll()
        googleNextData = nil
        googleAudio?.stop()
        googleAudio = nil
        isPlayingGoogle = false
        elevenQueue.removeAll()
        elevenPlayer?.stop()
        elevenPlayer = nil
        isPlayingEleven = false
        notifPlayer?.stop()
        notifPlayer = nil
        isSpeaking = false
        isPaused = false
        pendingCount = 0
        updateNowPlaying(playing: false)
        stopBackgroundMode()
    }

    /// Bỏ qua đoạn đang đọc, chuyển ngay sang đoạn tiếp theo trong hàng đợi (hữu ích khi live bình luận đông, đọc không kịp).
    func skipCurrent() {
        if isPlayingEleven {
            elevenPlayer?.stop()
            playNextEleven()
        } else if isPlayingGoogle {
            googleAudio?.stop()
            playNextGoogleItem()
        } else if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    // ElevenLabs phát xong 1 đoạn → đọc đoạn tiếp theo
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === elevenPlayer { playNextEleven() }
        else if player === googleAudio { playNextGoogleItem() }
    }

    func pauseOrContinue() {
        if isPlayingEleven {
            if isPaused { elevenPlayer?.play(); isPaused = false }
            else if isSpeaking { elevenPlayer?.pause(); isPaused = true }
        } else if engineType == .google {
            if isPaused {
                googleAudio?.play()
                isPaused = false
            } else if isSpeaking {
                googleAudio?.pause()
                isPaused = true
            }
        } else {
            if synth.isPaused { synth.continueSpeaking(); isPaused = false }
            else if synth.isSpeaking { synth.pauseSpeaking(at: .word); isPaused = true }
        }
    }

    func startBackgroundMode() {
        activateSession()
        guard let silentData = createSilentWAV() else { return }
        do {
            let player = try AVAudioPlayer(data: silentData)
            player.numberOfLoops = -1
            player.volume = 0.01
            player.prepareToPlay()
            player.play()
            self.silentPlayer = player
        } catch {
            print("Lỗi khởi tạo silent player: \(error)")
        }
    }
    
    func stopBackgroundMode() {
        silentPlayer?.stop()
        silentPlayer = nil
    }
    
    private func createSilentWAV() -> Data? {
        let sampleRate: Int32 = 8000
        let channels: Int16 = 1
        let bps: Int16 = 16
        let seconds = 2
        let byteRate = sampleRate * Int32(channels) * Int32(bps / 8)
        let blockAlign = channels * (bps / 8)
        let dataSize = byteRate * Int32(seconds)
        
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        var totalSizeLE = (dataSize + 36).littleEndian
        header.append(Data(bytes: &totalSizeLE, count: 4))
        header.append(contentsOf: "WAVEfmt ".utf8)
        var fmtSizeLE: Int32 = 16
        header.append(Data(bytes: &fmtSizeLE, count: 4))
        var formatLE: Int16 = 1 // PCM
        header.append(Data(bytes: &formatLE, count: 2))
        var channelsLE = channels.littleEndian
        header.append(Data(bytes: &channelsLE, count: 2))
        var sampleRateLE = sampleRate.littleEndian
        header.append(Data(bytes: &sampleRateLE, count: 4))
        var byteRateLE = byteRate.littleEndian
        header.append(Data(bytes: &byteRateLE, count: 4))
        var blockAlignLE = blockAlign.littleEndian
        header.append(Data(bytes: &blockAlignLE, count: 2))
        var bpsLE = bps.littleEndian
        header.append(Data(bytes: &bpsLE, count: 2))
        header.append(contentsOf: "data".utf8)
        var dataSizeLE = dataSize.littleEndian
        header.append(Data(bytes: &dataSizeLE, count: 4))
        
        let silence = Data(repeating: 0, count: Int(dataSize))
        header.append(silence)
        return header
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // delegate
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { isSpeaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        if !s.isSpeaking { isSpeaking = false; isPaused = false; updateNowPlaying(playing: false) }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { isSpeaking = false }
}
