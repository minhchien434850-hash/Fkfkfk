import SwiftUI
import AVFoundation
import MediaPlayer

// ======================== Engine TTS (đọc văn bản, phát nền) ========================
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

    private let synth = AVSpeechSynthesizer()
    private var silentPlayer: AVAudioPlayer?
    
    // Google TTS Queue
    private var googleQueue: [String] = []
    private var googlePlayer: AVPlayer?
    private var isPlayingGoogle = false

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
    @Published var rate: Float = UserDefaults.standard.object(forKey: "tts_rate") as? Float ?? AVSpeechUtteranceDefaultSpeechRate {
        didSet { UserDefaults.standard.set(rate, forKey: "tts_rate") }
    }
    @Published var pitch: Float = UserDefaults.standard.object(forKey: "tts_pitch") as? Float ?? 1.0 {
        didSet { UserDefaults.standard.set(pitch, forKey: "tts_pitch") }
    }
    @Published var volume: Float = UserDefaults.standard.object(forKey: "tts_volume") as? Float ?? 1.0 {
        didSet {
            UserDefaults.standard.set(volume, forKey: "tts_volume")
            // Cập nhật âm lượng ngay cho audio đang phát (Google / ElevenLabs), không cần đợi đọc câu mới.
            googlePlayer?.volume = volume
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
            if isPlayingGoogle, !isPaused { googlePlayer?.play() }
        }
    }

    /// Bật phiên audio dạng playback để tiếp tục đọc khi khoá màn hình / chuyển app khác.
    private func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? s.setActive(true, options: [])
    }

    func speak(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        case .elevenlabs:
            playElevenLabsTTS(t)
        case .system:
            playSystemTTS(t)
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
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let siriVoice = voices.first { v in
            v.language.hasPrefix("vi") && v.identifier.lowercased().contains("siri")
        } ?? voices.first { v in
            v.language.hasPrefix("vi")
        } ?? voices.first { v in
            v.identifier.lowercased().contains("siri")
        }
        
        if let v = siriVoice {
            u.voice = v
        }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)
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
    
    private func splitTextIntoChunks(_ text: String, maxLen: Int) -> [String] {
        var chunks: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".?!,;:\n"))
        
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if trimmed.count <= maxLen {
                chunks.append(trimmed)
            } else {
                let words = trimmed.components(separatedBy: .whitespacesAndNewlines)
                var currentChunk = ""
                
                for word in words {
                    let candidate = currentChunk.isEmpty ? word : "\(currentChunk) \(word)"
                    if candidate.count <= maxLen {
                        currentChunk = candidate
                    } else {
                        if !currentChunk.isEmpty {
                            chunks.append(currentChunk)
                        }
                        currentChunk = word
                    }
                }
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk)
                }
            }
        }
        return chunks
    }
    
    private func playNextGoogleItem() {
        guard !googleQueue.isEmpty else {
            isPlayingGoogle = false
            isSpeaking = false
            pendingCount = elevenQueue.count
            return
        }
        
        isPlayingGoogle = true
        isSpeaking = true
        let text = googleQueue.removeFirst()
        pendingCount = googleQueue.count + elevenQueue.count
        
        guard let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            playNextGoogleItem()
            return
        }
        
        let urlString = "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=tw-ob&q=\(encodedText)"
        guard let url = URL(string: urlString) else {
            playNextGoogleItem()
            return
        }
        
        // QUAN TRỌNG: Google chặn rất nhiều request không có User-Agent giống trình duyệt thật
        // (trả về lỗi hoặc audio rỗng) → luôn đính kèm User-Agent để giảm tỉ lệ bị từ chối.
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
            ]
        ])
        let playerItem = AVPlayerItem(asset: asset)
        
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(googleItemDidPlayToEndTime), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(googleItemFailedToPlay), name: .AVPlayerItemFailedToPlayToEndTime, object: playerItem)
        
        if googlePlayer == nil {
            googlePlayer = AVPlayer(playerItem: playerItem)
        } else {
            googlePlayer?.replaceCurrentItem(with: playerItem)
        }
        
        googlePlayer?.volume = volume
        googlePlayer?.play()
        
        // Timeout 5 giây: nếu Google không trả về audio → fallback offline
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.isPlayingGoogle else { return }
            if let status = self.googlePlayer?.currentItem?.status, status == .failed {
                // Google fail → dùng giọng offline nếu đang ở ElevenLabs mode
                if self.engineType == .elevenlabs {
                    self.playElevenLabsOfflineFallback(text)
                }
                self.playNextGoogleItem()
            }
        }
    }
    
    @objc private func googleItemDidPlayToEndTime(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.playNextGoogleItem()
        }
    }
    
    @objc private func googleItemFailedToPlay(notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.playNextGoogleItem()
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
        googlePlayer?.pause()
        googlePlayer = nil
        isPlayingGoogle = false
        elevenQueue.removeAll()
        elevenPlayer?.stop()
        elevenPlayer = nil
        isPlayingEleven = false
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
            googlePlayer?.pause()
            playNextGoogleItem()
        } else if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
    }

    // ElevenLabs phát xong 1 đoạn → đọc đoạn tiếp theo
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if player === elevenPlayer { playNextEleven() }
    }

    func pauseOrContinue() {
        if isPlayingEleven {
            if isPaused { elevenPlayer?.play(); isPaused = false }
            else if isSpeaking { elevenPlayer?.pause(); isPaused = true }
        } else if engineType == .google {
            if isPaused {
                googlePlayer?.play()
                isPaused = false
            } else if isSpeaking {
                googlePlayer?.pause()
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
