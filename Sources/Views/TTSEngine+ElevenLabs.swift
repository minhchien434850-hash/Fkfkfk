import AVFoundation

// Xây BODY request ElevenLabs ĐÚNG CHUẨN theo TỪNG MODEL (v3 khác hẳn v2) để "giống web 100%, không lỗi":
//  • Eleven v3 (eleven_v3): stability CHỈ nhận 0.0 / 0.5 / 1.0 — đúng 3 nút Creative / Natural / Robust
//    trên web (gửi số lẻ v3 sẽ bị làm tròn → lệch tông). Ta tự snap về mốc gần nhất. Hỗ trợ style +
//    speaker_boost + language_code. v3 còn hiểu "audio tags" như [excited] [whispers] [laughs] ngay trong text.
//  • Multilingual v2: KHÔNG gửi language_code (model này không hỗ trợ → tránh lỗi 400) và không snap stability.
func elevenLabsRequestBody(text: String, model: String,
                           stability: Double, similarityBoost: Double,
                           style: Double, speakerBoost: Bool) -> [String: Any] {
    let isV3 = (model == "eleven_v3")
    // v3: làm tròn stability về đúng 1 trong 3 mốc web dùng.
    let stab: Double = isV3
        ? [0.0, 0.5, 1.0].min(by: { abs($0 - stability) < abs($1 - stability) })!
        : stability
    let settings: [String: Any] = [
        "stability": stab,
        "similarity_boost": similarityBoost,
        "style": style,
        "use_speaker_boost": speakerBoost
    ]
    var body: [String: Any] = [
        "text": text,
        "model_id": model,
        "voice_settings": settings
    ]
    // language_code chỉ hợp lệ với model hỗ trợ (v3 / turbo v2.5 / flash v2.5) — multilingual_v2 thì bỏ.
    if model != "eleven_multilingual_v2" {
        body["language_code"] = "vi"
    }
    return body
}

// ======================== Giọng ElevenLabs (AI · đọc tiếng Việt) ========================
extension TTSEngine {

    func playElevenLabsTTS(_ text: String) {
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
    func playElevenLabsOfflineFallback(_ text: String) {
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

    func playElevenLabs(_ text: String) {
        elevenQueue.append(text)
        if elevenQueue.count > maxQueueSize {
            elevenQueue.removeFirst(elevenQueue.count - maxQueueSize)
        }
        pendingCount = googleQueue.count + elevenQueue.count
        if !isPlayingEleven { playNextEleven() }
    }

    func playNextEleven() {
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
        let body = elevenLabsRequestBody(text: text, model: model,
                                         stability: tone.stability,
                                         similarityBoost: tone.similarityBoost,
                                         style: tone.style, speakerBoost: tone.speakerBoost)
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
}
