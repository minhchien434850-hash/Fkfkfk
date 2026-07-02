import SwiftUI
import Foundation
import AVFoundation

// ============================================================================
//  MÔ-ĐUN ĐỘC LẬP: Đọc tiếng Việt CHUẨN (Siri vi-VN) + bộ lọc chuẩn hóa văn bản
//  - 100% cục bộ: chỉ dùng Foundation + AVFoundation (tương thích ESign).
//  - KHÔNG gọi máy chủ ngoài, KHÔNG SDK bên thứ ba.
//  - Luồng: Văn bản thô -> VietnameseTextNormalizer.normalize -> AVSpeechUtterance
//           -> AVSpeechSynthesizer (khóa giọng vi-VN, ưu tiên Siri/.enhanced).
// ============================================================================

// MARK: - Bộ chuẩn hóa văn bản tiếng Việt (mở rộng từ lóng/viết tắt + làm sạch)
struct VietnameseTextNormalizer {

    /// Từ điển phiên âm: viết tắt / tiếng lóng chat -> từ đầy đủ để TTS đọc đúng.
    /// Khóa luôn ở dạng CHỮ THƯỜNG; tra cứu theo từng "từ" nên không phá chữ bên trong từ khác.
    static let dictionary: [String: String] = [
        // --- Phủ định / khẳng định ---
        "ko": "không", "k": "không", "kg": "không", "khg": "không", "hok": "không",
        "hông": "không", "hong": "không", "kh": "không", "kp": "không phải",
        "đc": "được", "dc": "được", "đk": "được", "dk": "được",
        "uh": "ừ", "uk": "ừ", "um": "ừ", "ukm": "ừ", "okê": "ô kê", "oke": "ô kê",
        "ok": "ô kê", "okm": "ô kê", "okie": "ô kê",
        // --- Đại từ / xưng hô ---
        "mk": "mình", "mik": "mình", "mìh": "mình",
        "t": "tao", "tau": "tao", "tớ": "tớ",
        "bn": "bạn", "fr": "bạn",
        "ng": "người", "ngta": "người ta", "ngdung": "người dùng",
        "ae": "anh em", "ce": "chị em", "bme": "bố mẹ", "ny": "người yêu",
        // --- Hỏi / từ nối ---
        "j": "gì", "z": "vậy", "dz": "vậy", "zậy": "vậy", "vại": "vậy",
        "ntn": "như thế nào", "ny luôn": "luôn",
        "nhma": "nhưng mà", "nhưg": "nhưng", "vs": "với", "vows": "với",
        "ms": "mới", "r": "rồi", "rùi": "rồi", "roài": "rồi", "rồii": "rồi",
        "trc": "trước", "sd": "sử dụng", "sài": "xài",
        "h": "giờ", "bh": "bao giờ", "bjo": "bao giờ", "bao h": "bao giờ",
        "ns": "nói", "nc": "nói chuyện", "nt?": "như thế nào",
        // --- Tính từ / trạng từ ---
        "wa": "quá", "qá": "quá", "qua": "quá", "nhìu": "nhiều", "nhju": "nhiều",
        "ít": "ít", "iu": "yêu", "thik": "thích", "thíc": "thích",
        "bít": "biết", "bik": "biết", "bit": "biết", "bjk": "biết",
        "cũg": "cũng", "cug": "cũng", "đág": "đáng", "lém": "lắm", "lm": "làm",
        "zui": "vui", "zẻ": "rẻ", "zề": "về", "zô": "vô",
        // --- Cảm thán / tiếng lóng (làm sạch, đọc nhẹ) ---
        "vl": "vãi", "vcl": "vãi", "vkl": "vãi", "vc": "vãi",
        "clgt": "cái gì thế", "cmnr": "luôn rồi", "vlnr": "vãi luôn rồi",
        "gato": "ghen tị", "trùm": "trùm", "gg": "Google",
        "haha": "ha ha", "hihi": "hi hi", "huhu": "hu hu", "kk": "ha ha",
        // --- Địa danh / thương hiệu / thông dụng ---
        "vn": "Việt Nam", "hcm": "Hồ Chí Minh", "hn": "Hà Nội", "sg": "Sài Gòn",
        "đn": "Đà Nẵng", "fb": "Facebook", "ig": "Instagram", "insta": "Instagram",
        "yt": "YouTube", "tt": "TikTok", "tóp tóp": "TikTok", "zalo": "Za lô",
        "đt": "điện thoại", "mt": "máy tính", "lt": "laptop",
        "sp": "sản phẩm", " shop": "cửa hàng", "ad": "quản trị viên", "add": "kết bạn",
        "ship": "giao hàng", "order": "đặt hàng", "sale": "giảm giá",
        "cmt": "bình luận", "cmt nha": "bình luận nha", "sub": "đăng ký",
        "like": "thích", "share": "chia sẻ", "live": "phát trực tiếp",
        // --- Số / thời gian thông dụng ---
        "ah": "à", "à": "à", "nha": "nha", "nhé": "nhé", "nhaa": "nha",
        "đ": "đồng", "k đồng": "nghìn đồng", "tr": "triệu", "củ": "triệu",
        // --- Bổ sung thêm từ lóng / viết tắt thông dụng ---
        "cx": "cũng", "vậy nhỉ": "vậy nhỉ", "nma": "nhưng mà", "tks": "cảm ơn",
        "thanks": "cảm ơn", "ty": "cảm ơn", "sr": "xin lỗi", "sorry": "xin lỗi",
        "plz": "làm ơn", "pls": "làm ơn", "acc": "tài khoản", "pass": "mật khẩu",
        "user": "tài khoản", "gv": "giáo viên", "hs": "học sinh", "sv": "sinh viên",
        "ck": "chồng", "vk": "vợ", "e": "em", "a": "anh", "c": "chị", "b": "bạn",
        "đợi tí": "đợi tí", "nãy": "nãy", "z hả": "vậy hả", "tr?": "thật ạ",
        "vãi": "vãi", "trời": "trời", "ố dề": "ố dề", "chằm zn": "trầm cảm"
    ]

    /// Ký hiệu -> đọc thành chữ (để TTS không đọc máy móc hoặc bỏ qua).
    static let symbolMap: [String: String] = [
        "%": " phần trăm ", "&": " và ", "+": " cộng ", "=": " bằng ",
        "@": " a còng ", "<": " nhỏ hơn ", ">": " lớn hơn ",
        "₫": " đồng ", "°": " độ ", "×": " nhân ", "÷": " chia "
    ]

    /// Chuẩn hóa văn bản thô tiếng Việt trước khi đọc.
    /// `slang=false` → BỎ bộ lọc tiếng lóng (đọc nguyên văn hơn) nhưng vẫn dọn
    /// emoji/ký hiệu/số tiền. Dùng cho giọng iOS theo yêu cầu.
    static func normalize(_ text: String, slang: Bool = true) -> String {
        var s = text

        // 1) Đổi ký hiệu thành chữ.
        for (k, v) in symbolMap { s = s.replacingOccurrences(of: k, with: v) }

        // 1b) Đọc SỐ TIỀN viết tắt: 50k → "50 nghìn", 2tr → "2 triệu", 1tỷ → "1 tỷ",
        //     100000đ → "100000 đồng" (rất hợp cửa hàng). Chỉ áp khi số liền đơn vị.
        s = normalizeMoney(s)

        // 2) Bỏ emoji & ký tự lạ (giữ chữ, số, khoảng trắng, dấu câu cơ bản).
        s = String(String.UnicodeScalarView(s.unicodeScalars.map { sc in
            isAllowedScalar(sc) ? sc : Unicode.Scalar(32) // space
        }))

        // 2b) Mở rộng viết tắt CHÍNH THỐNG (sđt → số điện thoại, vd → ví dụ, vn → Việt Nam...)
        //     — LUÔN áp dụng (kể cả giọng iOS) để đọc tự nhiên, chuẩn hơn.
        s = replaceWords(s, using: formalAbbrev)

        // 3) Thay từng "từ" theo từ điển tiếng lóng (chỉ khi bật bộ lọc).
        if slang { s = replaceWords(s, using: dictionary) }

        // 4) Gom khoảng trắng, gọn dấu câu lặp (… , !!! , ??? ).
        s = collapse(s)

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Giữ lại: chữ cái (mọi ngôn ngữ, gồm tiếng Việt có dấu), chữ số, khoảng trắng, dấu câu cơ bản.
    private static let punctuation: Set<Character> = [".", ",", "!", "?", ";", ":", "-", "(", ")", "\"", "'", "\n"]
    private static func isAllowedScalar(_ sc: Unicode.Scalar) -> Bool {
        if sc.properties.isAlphabetic { return true }
        if ("0"..."9").contains(Character(sc)) { return true }
        if sc == " " || sc == "\n" || sc == "\t" { return true }
        return punctuation.contains(Character(sc))
    }

    // Đọc số tiền viết tắt bằng regex: bắt "<số>" + đơn vị (k/tr/tỷ/ty/đ/d) đứng liền,
    // ranh giới sau là hết từ (không phải chữ cái) → tránh phá "trung", "kính"...
    private static func normalizeMoney(_ text: String) -> String {
        var s = text
        let rules: [(String, String)] = [
            ("(\\d+)\\s*tỷ\\b", "$1 tỷ"),
            ("(\\d+)\\s*(tr|triệu)\\b", "$1 triệu"),
            ("(\\d+)\\s*(k|nghìn|ngàn)\\b", "$1 nghìn"),
            ("(\\d+)\\s*(đ|d|vnđ|vnd)\\b", "$1 đồng")
        ]
        for (pat, rep) in rules {
            if let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                let range = NSRange(s.startIndex..<s.endIndex, in: s)
                s = re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: rep)
            }
        }
        return s
    }

    // Viết tắt chính thống → đọc đầy đủ (an toàn, không phải tiếng lóng), luôn áp dụng.
    static let formalAbbrev: [String: String] = [
        "sđt": "số điện thoại", "sdt": "số điện thoại",
        "stk": "số tài khoản", "tphcm": "thành phố Hồ Chí Minh",
        "vd": "ví dụ", "vv": "vân vân",
        "vn": "Việt Nam", "sl": "số lượng",
        "kg": "ki lô", "km": "ki lô mét",
        "tp": "thành phố"
    ]

    // Tách theo "từ" = chuỗi chữ cái/chữ số liền nhau; phần còn lại giữ nguyên.
    private static func replaceWords(_ text: String, using dict: [String: String]) -> String {
        var out = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            if let rep = dict[token.lowercased()] {
                out += rep
            } else {
                out += token
            }
            token = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber {
                token.append(ch)
            } else {
                flush()
                out.append(ch)
            }
        }
        flush()
        return out
    }

    // Gom khoảng trắng thừa và dấu câu lặp để câu đọc mượt, không khựng.
    private static func collapse(_ text: String) -> String {
        var s = text
        // "…" và nhiều dấu chấm -> 1 dấu chấm
        s = s.replacingOccurrences(of: "…", with: ".")
        while s.contains("..") { s = s.replacingOccurrences(of: "..", with: ".") }
        while s.contains("!!") { s = s.replacingOccurrences(of: "!!", with: "!") }
        while s.contains("??") { s = s.replacingOccurrences(of: "??", with: "?") }
        // Nhiều khoảng trắng -> 1
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        s = s.replacingOccurrences(of: " ,", with: ",")
        s = s.replacingOccurrences(of: " .", with: ".")
        return s
    }
}

// MARK: - Trình phát giọng nói (KHÓA vi-VN, ưu tiên Siri / .enhanced)
final class VietnameseSiriSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    @Published var isSpeaking = false
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var pitch: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var voiceName: String = ""

    override init() {
        super.init()
        synth.delegate = self
        voiceName = lockedVietnameseVoice()?.name ?? "Không có giọng vi-VN"
    }

    /// Khóa CHẶT vào tiếng Việt: ưu tiên premium (Siri) > enhanced (Siri) > bất kỳ giọng vi.
    func lockedVietnameseVoice() -> AVSpeechSynthesisVoice? {
        let vi = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("vi") }
        return vi.first { $0.quality == .premium }
            ?? vi.first { $0.quality == .enhanced }
            ?? vi.first
            ?? AVSpeechSynthesisVoice(language: "vi-VN")
    }

    /// Đọc: chuẩn hóa văn bản -> tạo utterance -> phát bằng giọng vi-VN.
    func speak(_ raw: String) {
        // Giọng iOS: bỏ bộ lọc tiếng lóng, chỉ giữ chuẩn hóa số tiền/ký hiệu/emoji
        let text = VietnameseTextNormalizer.normalize(raw, slang: false)
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = lockedVietnameseVoice()   // KHÓA vi-VN, không cho ngôn ngữ khác
        u.rate = rate
        u.pitchMultiplier = pitch
        u.volume = volume
        u.preUtteranceDelay = 0.0
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate); isSpeaking = false }

    // delegate
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { isSpeaking = true }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { if !s.isSpeaking { isSpeaking = false } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { isSpeaking = false }
}

// MARK: - Giao diện độc lập
struct VietnameseSiriTTSView: View {
    @StateObject private var speaker = VietnameseSiriSpeaker()
    @State private var input = "Vd: Sản phẩm giá 250k, ưu đãi còn 199k 🎉"

    private var preview: String { VietnameseTextNormalizer.normalize(input, slang: false) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                VStack(alignment: .leading, spacing: 6) {
                    Label("Giọng đang dùng", systemImage: "person.wave.2.fill")
                        .font(.subheadline.bold())
                    Text(speaker.voiceName).font(.caption).foregroundStyle(.secondary)
                    Text("Khóa cố định tiếng Việt (vi-VN), ưu tiên giọng Siri/Cao cấp. Chạy cục bộ, không cần mạng.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Văn bản (có thể viết tắt / tiếng lóng)").font(.subheadline.bold())
                TextEditor(text: $input)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Label("Sau khi lọc (sẽ đọc)", systemImage: "wand.and.stars")
                        .font(.caption.bold()).foregroundStyle(.green)
                    Text(preview.isEmpty ? "—" : preview)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.green.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 8) {
                    sliderRow("Tốc độ", value: $speaker.rate,
                              range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                    sliderRow("Cao độ", value: $speaker.pitch, range: 0.5...2.0)
                    sliderRow("Âm lượng", value: $speaker.volume, range: 0...1)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack {
                    Button { speaker.speak(input) } label: {
                        Label("Đọc", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button { speaker.stop() } label: {
                        Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Đọc tiếng Việt chuẩn")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }

    private func sliderRow(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
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
