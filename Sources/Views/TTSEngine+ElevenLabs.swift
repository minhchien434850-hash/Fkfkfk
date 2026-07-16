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
    // v3: TỰ THÊM THẺ CẢM XÚC theo nội dung (vd bình luận vui → [laughs], hype → [excited])
    // cho giọng sinh động hơn. Chỉ v3 hiểu thẻ; v2 sẽ đọc thành chữ nên KHÔNG thêm.
    // Tôn trọng lựa chọn người dùng (tắt được) và KHÔNG thêm nếu họ đã tự gõ thẻ.
    var outText = text
    if isV3 && UserDefaults.standard.object(forKey: "eleven_auto_emotion") as? Bool != false {
        let tag = elevenLabsAutoEmotionTag(for: text)
        if !tag.isEmpty && !text.trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            outText = tag + " " + text
        }
    }
    var body: [String: Any] = [
        "text": outText,
        "model_id": model,
        "voice_settings": settings
    ]
    // language_code chỉ hợp lệ với model hỗ trợ (v3 / turbo v2.5 / flash v2.5) — multilingual_v2 thì bỏ.
    if model != "eleven_multilingual_v2" {
        body["language_code"] = "vi"
    }
    return body
}

// ======================== Bộ PHÂN TÍCH CẢM XÚC v3 (đa dạng · đa tầng · hợp ngữ cảnh) ========================
// Nhận diện nội dung bình luận rồi chèn 1–3 thẻ cảm xúc v3 hợp ngữ cảnh, KHÁC nhau theo:
//  • Toxic/khịa → giọng cà khịa/thở dài/coi thường (không "quạo" lại).
//  • Vui/hype/dễ thương/buồn/tò mò/chào hỏi… → thẻ tương ứng.
//  • MỨC ĐỘ (dấu !, chữ HOA, emoji, kéo dàiii) → càng mạnh càng NHIỀU thẻ (tối đa 3).
// Trả về chuỗi thẻ ghép sẵn, vd "[excited][happy]" (hoặc "" nếu câu quá trung tính).

// Một nhóm cảm xúc: các dấu hiệu (từ khoá/emoji) + thẻ v3 tương ứng + độ ưu tiên.
private struct EmotionRule {
    let tag: String
    let priority: Int          // cao = ưu tiên chọn trước
    let cues: [String]
}

// Danh sách thẻ v3 phong phú (đã gộp hầu hết thẻ audio v3 dùng tốt cho đọc bình luận).
private let kEmotionRules: [EmotionRule] = [
    // Cười — nhiều mức
    .init(tag: "[laughs harder]", priority: 95, cues: ["hahaha", "kkkk", "xỉu ngang", "cười xỉu", "té ghế", "🤣🤣", "😂😂😂"]),
    .init(tag: "[laughs]",   priority: 80, cues: ["haha", "hehe", "kaka", "kkk", "😂", "🤣", "😆", "😹", "buồn cười", "vui quá", "cười", "lol", "lmao", "=))", ":))", "vãi cười"]),
    .init(tag: "[giggles]",  priority: 60, cues: ["hihi", "hí hí", "uwu", "khì khì", "cười khúc khích", "mắc cười"]),
    // Dễ thương / ấm áp / tình cảm
    .init(tag: "[warmly]",   priority: 58, cues: ["dễ thương", "cưng", "iu", "yêu quá", "đáng yêu", "thương", "cute", "🥰", "😘", "😍", "💕", "❤️", "🤗"]),
    // Hype / phấn khích — nhiều mức
    .init(tag: "[shouts]",   priority: 92, cues: ["!!!", "aaaaa", "quá đỉnh luôn", "cháy quá", "khét lẹt", "gọiii"]),
    .init(tag: "[excited]",  priority: 82, cues: ["🔥", "💯", "🤩", "⚡", "đỉnh", "tuyệt vời", "quá đỉnh", "vô địch", "khủng", "cực", "vãi", "xuất sắc", "number one", "quá hay", "quá đã", "gớm", "bá cháy", "cháy", "mãi đỉnh", "gánh team", "pro", "trùm"]),
    .init(tag: "[dramatically]", priority: 40, cues: ["huyền thoại", "lịch sử", "epic", "khủng khiếp", "không thể tin"]),
    // Vui vẻ / chào hỏi / cảm ơn / tặng quà / follow
    .init(tag: "[happy]",    priority: 55, cues: ["cảm ơn", "cám ơn", "thank", "chào", "xin chào", "hello", "welcome", "hi shop", "tặng", "quà", "yêu mọi người", "theo dõi", "follow", "đã sub", "chia sẻ", "share", "chúc mừng", "🎉", "🎁", "👋", "🥳", "😊", "😄"]),
    // Bất ngờ
    .init(tag: "[gasps]",    priority: 70, cues: ["😱", "😲", "😮", "trời ơi", "trời đất", "ôi trời", "gì vậy trời", "thật hả", "thật á", "hả???", "gì cơ", "khoan đã", "ủa"]),
    .init(tag: "[surprised]", priority: 50, cues: ["wow", "wao", "oào", "không thể nào", "bất ngờ", "gì thế", "ơ kìa"]),
    // Buồn / thương cảm — nhiều mức
    .init(tag: "[crying]",   priority: 88, cues: ["😭", "😭😭", "khóc thét", "khóc quá", "hu hu hu"]),
    .init(tag: "[sad]",      priority: 68, cues: ["😢", "😔", "🥺", "buồn", "khóc", "tội nghiệp", "chia buồn", "thất vọng", "huhu", "chán quá", "nhớ quá", "cô đơn", "tiếc quá", "hụt hẫng"]),
    // Tò mò / hỏi
    .init(tag: "[curious]",  priority: 45, cues: ["?", "tại sao", "vì sao", "sao vậy", "thế nào", "là gì", "ở đâu", "bao nhiêu", "khi nào", "ai vậy", "cho hỏi", "thắc mắc"]),
    // Nhẹ nhàng / thì thầm / ngại
    .init(tag: "[whispers]", priority: 38, cues: ["thì thầm", "nói nhỏ", "bí mật", "ngại quá", "xấu hổ", "hihi bí mật", "nhẹ nhàng"]),
    // Hồi hộp / lo lắng
    .init(tag: "[nervous]",  priority: 42, cues: ["hồi hộp", "lo quá", "run quá", "sợ quá", "căng thẳng", "😰", "😨", "tim đập"]),
    // Bực / khó chịu (KHÔNG toxic — chỉ than phiền)
    .init(tag: "[frustrated]", priority: 44, cues: ["bực", "tức ghê", "khó chịu", "chán ghê", "phiền quá", "😤", "😠", "lag quá", "giật quá", "mệt mỏi"]),
    // Mệt / thở dài
    .init(tag: "[sighs]",    priority: 30, cues: ["mệt quá", "thôi kệ", "haizz", "haiz", "chán thật", "thở dài", "uầy"]),
]

// Toxic / khịa → phản ứng cà khịa – coi thường – thở dài (KHÔNG gắt lại). Ưu tiên tuyệt đối.
private let kToxicCues: [String] = [
    "đm", "dm", "đmm", "vcl", "vkl", " vl", " cl", "cc", "clm", "cmm", "đjt", "địt", "dcm", "đcm",
    "ngu", "óc chó", "oc cho", "súc vật", "suc vat", "chó má", "cho ma", "đồ chó", "khốn", "mất dạy",
    "não phẳng", "nao phang", "thằng ngu", "con ngu", "im mồm", "im đi", "câm", "cút", "rác", "lũ",
    "vô học", "vo hoc", "đần", "dốt", "kém", "gà", "noob", "phế", "yếu", "🤬", "🖕", "vãi lồn"
]
private let kToxicTags: [String] = ["[sarcastic]", "[unimpressed]", "[sighs]", "[chuckles]", "[dismissive]"]

// Trả về chuỗi 1–3 thẻ (vd "[excited][happy]") theo nội dung & mức độ của câu. "" nếu quá trung tính.
func elevenLabsAutoEmotionTag(for text: String) -> String {
    let s = text.lowercased()
    if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }

    // 1) TOXIC/khịa → nhánh riêng: cà khịa, không gắt lại. Mức càng nặng chọn càng nhiều thẻ.
    let toxicHits = kToxicCues.filter { s.contains($0) }.count
    if toxicHits > 0 {
        let n = min(1 + toxicHits / 2, 3)
        return Array(kToxicTags.prefix(n)).joined()
    }

    // 2) Chấm điểm các nhóm cảm xúc theo dấu hiệu khớp.
    var matched: [(tag: String, score: Int)] = []
    for r in kEmotionRules {
        let hits = r.cues.filter { s.contains($0) }.count
        if hits > 0 { matched.append((r.tag, r.priority + hits * 5)) }
    }
    if matched.isEmpty { return "" }

    // 3) MỨC ĐỘ cảm xúc → quyết định số thẻ (1–3).
    let bangs = s.filter { $0 == "!" }.count
    let emojiCount = text.unicodeScalars.filter { $0.properties.isEmoji && $0.value > 0x238C }.count
    let elongated = hasElongation(s)                 // "quááá", "hayyy", "đỉnhhh"
    let capsShout = hasAllCapsWord(text)             // "TUYỆT VỜI"
    var intensity = 0
    intensity += min(bangs, 2)                       // tối đa +2 do dấu !
    intensity += min(emojiCount, 2)                  // tối đa +2 do emoji
    if elongated { intensity += 1 }
    if capsShout { intensity += 1 }
    if matched.count >= 2 { intensity += 1 }         // nhiều loại cảm xúc → mạnh hơn

    let count = intensity >= 4 ? 3 : (intensity >= 2 ? 2 : 1)

    // 4) Chọn `count` thẻ điểm cao nhất (loại trùng), giữ đa dạng.
    var seen = Set<String>()
    let ordered = matched.sorted { $0.score > $1.score }
        .map { $0.tag }.filter { seen.insert($0).inserted }
    return Array(ordered.prefix(count)).joined()
}

// Có ký tự lặp ≥3 lần liên tiếp (dấu hiệu "kéo dài" cảm xúc): "quááá", "hayyy", "đỉnhhhh".
private func hasElongation(_ s: String) -> Bool {
    var prev: Character? = nil; var run = 1
    for ch in s where !ch.isWhitespace {
        if ch == prev { run += 1; if run >= 3 { return true } }
        else { prev = ch; run = 1 }
    }
    return false
}

// Có từ VIẾT HOA toàn bộ (≥2 chữ) → hô hào/nhấn mạnh: "TUYỆT", "ĐỈNH".
private func hasAllCapsWord(_ text: String) -> Bool {
    for w in text.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
        let letters = w.filter { $0.isLetter }
        if letters.count >= 2 && letters.allSatisfy({ $0.isUppercase }) { return true }
    }
    return false
}

// ======================== Giọng ElevenLabs (AI · đọc tiếng Việt) ========================
extension TTSEngine {

    func playElevenLabsTTS(_ text: String, priority: Bool = false) {
        // Dùng ElevenLabs chỉ khi có cả API key VÀ Voice ID
        let key = elevenKey.trimmingCharacters(in: .whitespaces)
        let vid = elevenVoiceId.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty && !vid.isEmpty {
            playElevenLabs(text, priority: priority)
            return
        }
        // Chưa nhập Voice ID → fallback Google TTS
        playGoogleTTS(text, priority: priority)
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

    func playElevenLabs(_ text: String, priority: Bool = false) {
        // Ưu tiên (follow/tặng quà/chia sẻ) → chèn LÊN ĐẦU để đọc trước bình luận thường.
        // KHÔNG cắt bỏ hàng đợi nữa: đọc ĐẦY ĐỦ từng bình luận, xong mới sang cái kế tiếp.
        if priority { elevenQueue.insert(text, at: 0) }
        else { elevenQueue.append(text) }
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
