import AVFoundation

// ======================== Giọng iOS · Siri · Siri-Anh phiên âm ========================
extension TTSEngine {

    func playSystemTTS(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        if let v = AVSpeechSynthesisVoice(identifier: voiceId) { u.voice = v }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)          // tự xếp hàng nếu đang đọc cái khác
    }

    func playSiriTTS(_ text: String) {
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
    func bestSiriVoice() -> AVSpeechSynthesisVoice? {
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
    func playSiriEnViTTS(_ text: String) {
        let phonetic = Self.vietnameseToEnglishPhonetic(text)
        let u = AVSpeechUtterance(string: phonetic)
        if let v = bestEnglishVoice() { u.voice = v }
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        synth.speak(u)
    }

    // Chọn giọng tiếng Anh tốt nhất (ưu tiên Siri en, rồi premium/enhanced).
    func bestEnglishVoice() -> AVSpeechSynthesisVoice? {
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
    static func detoneKeepVowelQuality(_ s: String) -> String {
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
}
