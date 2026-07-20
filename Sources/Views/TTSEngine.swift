import SwiftUI
import AVFoundation
import MediaPlayer

// ======================== Engine TTS (đọc văn bản, phát nền) ========================
// FILE CHÍNH: khai báo class + TOÀN BỘ stored property + vòng đời + điều khiển phát chung.
// Các nhóm chức năng tách sang file extension cho dễ kiểm soát:
//   • TTSEngine+Voices.swift      — giọng iOS / Siri / Siri-Anh phiên âm
//   • TTSEngine+Google.swift      — Chị Google (online, prefetch)
//   • TTSEngine+ElevenLabs.swift  — giọng ElevenLabs (AI)
//   • TTSEngine+Sounds.swift      — âm thanh thông báo (quà/follow/share)
//   • TTSEngine+Background.swift  — chạy nền, Now Playing, Control Center
final class TTSEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    enum EngineType: String, CaseIterable, Identifiable {
        case system = "system"
        case google = "google"
        case siri = "siri"
        case elevenlabs = "elevenlabs"

        var id: String { self.rawValue }
        var label: String {
            switch self {
            case .system: return "Mặc định (iOS)"
            case .google: return "Chị Google (Online)"
            case .siri: return "Giọng Siri (iOS)"
            case .elevenlabs: return "Giọng ElevenLabs"
            }
        }
    }

    let synth = AVSpeechSynthesizer()
    var silentPlayer: AVAudioPlayer?
    var notifPlayer: AVAudioPlayer?   // phát âm thanh thông báo (follow/quà/share…) TRƯỚC khi đọc
    var notifDataCache: [String: Data] = [:]   // cache audio meme tải từ link (khỏi tải lại mỗi lần)

    // Google TTS Queue
    var googleQueue: [String] = []
    var googleAudio: AVAudioPlayer?      // phát từ Data đã tải sẵn (mượt, không khoảng lặng)
    var googleNextData: Data?            // PREFETCH: audio của đoạn KẾ đã tải sẵn trong lúc đọc đoạn này
    var isPlayingGoogle = false
    var googleItemToken = 0   // chống "kẹt" 1 đoạn: watchdog so khớp token

    // Tốc độ phát cho Google (map thanh rate → bội số 0.5x…2.0x; mặc định rate 0.5 = 1.0x)
    var googleSpeed: Float { max(0.5, min(2.0, rate * 2.0)) }

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

    // KEY DÙNG CHUNG do ADMIN đặt trên MÁY CHỦ. Khi bật, app đọc ElevenLabs qua máy chủ
    // (POST serverBase/tts/eleven) → khách CHỈ cần nhập Voice ID, không cần & không thấy key.
    @Published var elevenServerKey: Bool = false
    var serverBase: String = ""       // URL máy chủ (do AppStore bơm vào)
    var serverToken: String? = nil    // token đăng nhập để gọi /tts/eleven
    // Tốc độ đọc ElevenLabs (0.7 chậm → 1.2 nhanh; 1.0 = bình thường). Ai cũng chỉnh được (lưu máy).
    @Published var elevenSpeed: Double = (UserDefaults.standard.object(forKey: "eleven_speed") as? Double) ?? 1.0 {
        didSet { UserDefaults.standard.set(elevenSpeed, forKey: "eleven_speed") }
    }

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
    var currentTone: ElevenTonePreset {
        kElevenTonePresets.first { $0.id == elevenToneId } ?? kElevenTonePresets[0]
    }
    var elevenPlayer: AVAudioPlayer?
    var elevenQueue: [String] = []
    var isPlayingEleven = false

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
    func activateSession() {
        let s = AVAudioSession.sharedInstance()
        // KHÔNG dùng .duckOthers → không hạ/tắt âm lượng nhạc app khác (Spotify/YouTube...).
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? s.setActive(true, options: [])
    }

    /// priority=true (follow/tặng quà/chia sẻ) → CHÈN LÊN ĐẦU hàng đợi để đọc TRƯỚC bình luận.
    func speak(_ text: String, priority: Bool = false) {
        // Chuẩn hóa văn bản:
        // · ElevenLabs: GIỮ NGUYÊN văn bản gốc (model tự xử lý ngữ điệu/cảm xúc).
        // · Chị Google: chuẩn hóa đầy đủ (kèm mở rộng tiếng lóng).
        // · Giọng iOS (mặc định · Siri · Siri Anh-Việt): BỎ bộ lọc tiếng lóng,
        //   chỉ giữ chuẩn hóa số tiền/ký hiệu/emoji để đọc tự nhiên, mượt hơn.
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t: String
        switch engineType {
        case .elevenlabs: t = raw
        case .google:     t = VietnameseTextNormalizer.normalize(raw)
        default:          t = VietnameseTextNormalizer.normalize(raw, slang: false)
        }
        guard !t.isEmpty else { return }
        activateSession()
        // Tự bật chế độ nền (giữ audio sống khi chuyển app / khoá màn hình)
        if silentPlayer == nil { startBackgroundMode() }
        updateNowPlaying(playing: true)   // hiện ở Control Center / màn khoá

        switch engineType {
        case .google:
            playGoogleTTS(t, priority: priority)
        case .siri:
            playSiriTTS(t)
        case .elevenlabs:
            playElevenLabsTTS(t, priority: priority)
        case .system:
            playSystemTTS(t)
        }
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

    // ElevenLabs / Google phát xong 1 đoạn → đọc đoạn tiếp theo
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // delegate AVSpeechSynthesizer
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { isSpeaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        if !s.isSpeaking { isSpeaking = false; isPaused = false; updateNowPlaying(playing: false) }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { isSpeaking = false }
}
