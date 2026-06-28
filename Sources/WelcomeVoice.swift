import AVFoundation

/// Phát lời chào tiếng nói khi mở app — có thể cấu hình nội dung, giọng & tốc độ từ Settings.
final class WelcomeVoice: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = WelcomeVoice()

    nonisolated(unsafe) private let synth = AVSpeechSynthesizer()
    nonisolated(unsafe) private var spokenOnce = false
    nonisolated(unsafe) private var googlePlayer: AVPlayer?   // giọng "chị Google" (online, như TTS Live)

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Phát lời chào một lần duy nhất khi mở app (0.8s sau khi UI sẵn sàng)
    func playOnce(text: String, voiceId: String, rate: Float) {
        guard !spokenOnce else { return }
        spokenOnce = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.speak(text: text, voiceId: voiceId, rate: rate)
        }
    }

    /// Phát thử từ Settings (không giới hạn số lần)
    func testSpeak(text: String, voiceId: String, rate: Float) {
        synth.stopSpeaking(at: .immediate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.speak(text: text, voiceId: voiceId, rate: rate)
        }
    }

    /// Dừng phát
    func stop() {
        synth.stopSpeaking(at: .immediate)
        googlePlayer?.pause(); googlePlayer = nil
    }

    /// Phát bằng giọng "chị Google" (online) — giống TTS Live
    private func playGoogle(_ text: String) {
        let chunk = String(text.prefix(190))
        guard let enc = chunk.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=tw-ob&q=\(enc)")
        else { return }
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(playerItem: item)
        googlePlayer = p
        p.play()
    }

    private func speak(text: String, voiceId: String, rate: Float) {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Xin chào" : text
        // Giọng "chị Google" online — giống động cơ Google trong TTS Live
        if voiceId == "google" {
            playGoogle(content); return
        }
        let utterance = AVSpeechUtterance(string: content)
        if voiceId.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN")
        } else {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
                ?? AVSpeechSynthesisVoice(language: "vi-VN")
        }
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate,
                             min(AVSpeechUtteranceMaximumSpeechRate, rate))
        utterance.pitchMultiplier = 1.05
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}

    // MARK: - Danh sách giọng đọc có sẵn
    /// Ưu tiên tiếng Việt → Anh (US/GB/AU) → Trung/Nhật/Hàn
    static var availableVoices: [AVSpeechSynthesisVoice] {
        let priority = ["vi", "en-US", "en-GB", "en-AU", "zh-CN", "ja-JP", "ko-KR", "th-TH", "fr-FR"]
        return AVSpeechSynthesisVoice.speechVoices().sorted { a, b in
            let ai = priority.firstIndex(where: { a.language.hasPrefix($0) }) ?? 99
            let bi = priority.firstIndex(where: { b.language.hasPrefix($0) }) ?? 99
            if ai != bi { return ai < bi }
            return a.quality.rawValue > b.quality.rawValue
        }
    }

    /// Tên hiển thị đẹp cho một giọng đọc
    static func displayName(_ v: AVSpeechSynthesisVoice) -> String {
        let qual: String
        switch v.quality {
        case .enhanced: qual = " ✦"
        default: qual = ""
        }
        return "\(v.name)\(qual) · \(v.language)"
    }
}
