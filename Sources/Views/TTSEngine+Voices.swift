import AVFoundation
import NaturalLanguage

// ======================== Giọng iOS · Siri · Siri-Anh phiên âm ========================
extension TTSEngine {

    func playSystemTTS(_ text: String) {
        let v = AVSpeechSynthesisVoice(identifier: voiceId)
        speakExpressive(text, voice: v)   // đọc biểu cảm, tự xếp hàng nếu đang đọc cái khác
    }

    func playSiriTTS(_ text: String) {
        // Ưu tiên giọng người dùng tự chọn trong app; nếu chưa chọn thì tự lấy giọng tốt nhất.
        let voice: AVSpeechSynthesisVoice? = {
            if !siriVoiceId.isEmpty, let v = AVSpeechSynthesisVoice(identifier: siriVoiceId) { return v }
            return bestSiriVoice()
        }()
        speakExpressive(text, voice: voice)
    }

    // ===== Bộ đọc BIỂU CẢM cho giọng iOS =====
    // Tách câu theo dấu câu rồi đọc từng câu với ngữ điệu (cao độ/tốc độ/ngắt nghỉ)
    // phù hợp: câu hỏi lên giọng, câu cảm thán mạnh hơn, ngắt nghỉ tự nhiên giữa các câu.
    // Câu đầu tiên KHÔNG có độ trễ để giữ độ trễ siêu thấp khi bắt đầu đọc.
    func speakExpressive(_ text: String, voice: AVSpeechSynthesisVoice?) {
        let sentences = Self.splitSentences(text)
        guard !sentences.isEmpty else { return }
        // Chuẩn bị sẵn giọng tiếng Anh để đọc ĐA NGÔN NGỮ (câu tiếng Anh xen giữa).
        let enVoice = bestEnglishVoice()
        for (idx, s) in sentences.enumerated() {
            let u = AVSpeechUtterance(string: s)
            // ĐA NGÔN NGỮ: câu nào là tiếng Anh → đọc bằng giọng Anh, còn lại giữ giọng chính (Việt).
            if Self.isEnglishSentence(s), let en = enVoice {
                u.voice = en
            } else {
                u.voice = voice
            }
            u.volume = volume

            var r = rate
            var p = pitch
            var vol = volume
            let last = s.last
            if last == "?" || last == "？" {
                // Câu hỏi: hơi chậm cuối câu + lên giọng.
                p = min(2.0, pitch * 1.06); r = rate * 0.97
            } else if last == "!" || last == "！" {
                // Câu cảm thán: mạnh & rõ hơn một chút.
                p = min(2.0, pitch * 1.04); vol = min(1.0, volume * 1.10); r = rate * 1.02
            } else if last == "…" || s.hasSuffix("...") {
                // Câu bỏ lửng: nhẹ & chậm lại.
                p = max(0.5, pitch * 0.97); r = rate * 0.95
            }
            u.rate = r
            u.pitchMultiplier = p
            u.volume = vol

            // Ngắt nghỉ tự nhiên giữa các câu; câu đầu không trễ (độ trễ siêu thấp).
            u.preUtteranceDelay = idx == 0 ? 0.0 : 0.12
            // Câu có nhiều dấu phẩy → thêm nhịp nghỉ nhẹ ở cuối cho tự nhiên.
            u.postUtteranceDelay = s.contains(",") ? 0.10 : 0.02
            synth.speak(u)
        }
    }

    // Tách văn bản thành các câu, GIỮ dấu câu cuối để suy ra ngữ điệu.
    static func splitSentences(_ text: String) -> [String] {
        var result: [String] = []
        var cur = ""
        for ch in text {
            cur.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "…" || ch == "。" || ch == "！" || ch == "？" || ch == "\n" {
                let t = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { result.append(t) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        // Nếu văn bản không có dấu câu nào → đọc nguyên đoạn.
        if result.isEmpty {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { result.append(t) }
        }
        return result
    }

    // Nhận diện câu tiếng Anh (để đọc đa ngôn ngữ).
    // Có dấu tiếng Việt → chắc chắn KHÔNG phải tiếng Anh (nhanh, tránh gọi bộ nhận diện).
    static func isEnglishSentence(_ s: String) -> Bool {
        let viChars = Set("ăâêôơưđàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ")
        let lower = s.lowercased()
        if lower.contains(where: { viChars.contains($0) }) { return false }
        // Cần tối thiểu vài chữ cái mới đáng nhận diện; câu quá ngắn coi như tiếng Việt (an toàn).
        let letters = lower.filter { $0.isLetter }
        guard letters.count >= 3 else { return false }
        let rec = NLLanguageRecognizer()
        rec.processString(s)
        return rec.dominantLanguage == .english
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
