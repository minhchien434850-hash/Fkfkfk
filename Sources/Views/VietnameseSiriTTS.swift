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
    /// (Từ tục/chửi thề dạng viết tắt KHÔNG có nguyên âm — vd vcl, sml, dm — sẽ tự được
    ///  ĐÁNH VẦN thành tên chữ cái tiếng Việt "vờ cờ lờ", "sờ mờ lờ"… ở bước dự phòng bên dưới,
    ///  vừa đọc rõ vừa tránh phát nguyên văn từ tục trên live.)
    static let dictionary: [String: String] = [
        // --- Phủ định / khẳng định ---
        "ko": "không", "k": "không", "kk": "không", "kg": "không", "khg": "không",
        "hok": "không", "hem": "không", "hong": "không", "hông": "không", "kô": "không",
        "kh": "không", "kbt": "không biết", "ksg": "không sao đâu", "ks": "không sao",
        "klq": "không liên quan", "knh": "không nha", "kma": "không mà", "kmr": "không mà",
        "kbh": "không bao giờ", "kdc": "không được", "kđc": "không được", "dko": "được không",
        "kmb": "không muốn biết", "kns": "không nói sai",
        "dc": "được", "đc": "được", "dk": "được", "đk": "được", "đx": "được",
        "đr": "đúng rồi", "chx": "chưa",
        "uh": "ừ", "uk": "ừ", "um": "ừ", "ukm": "ừ", "ok": "ô kê", "oke": "ô kê",
        "okê": "ô kê", "okm": "ô kê", "okie": "ô kê",
        // --- Đại từ / xưng hô ---
        "mk": "mật khẩu", "mik": "mình", "mìh": "mình",
        "t": "tôi", "tau": "tao", "tui": "tui", "tớ": "tớ", "m": "mày",
        "bn": "bạn", "b": "bạn", "bb": "bạn", "ng": "người", "ngta": "người ta",
        "mn": "mọi người", "mng": "mọi người", "gđ": "gia đình", "ae": "anh em",
        "ce": "chị em", "bme": "bố mẹ", "ny": "người yêu", "nyc": "người yêu cũ",
        "nym": "người yêu mới", "cr": "crush", "fa": "độc thân", "vk": "vợ",
        "ck": "chồng", "p3": "bạn bè", "e": "em", "a": "anh", "c": "chị",
        // --- Hỏi / vậy / từ nối ---
        "j": "gì", "cj": "cái gì", "s": "sao", "sa": "sao",
        "z": "vậy", "v": "vậy", "zay": "vậy", "zậy": "vậy", "dz": "vậy",
        "vt": "vậy ta", "vtr": "vậy trời", "ntn": "như thế nào",
        "nhma": "nhưng mà", "nma": "nhưng mà", "nhưg": "nhưng", "vs": "với",
        "ms": "mới", "r": "rồi", "rùi": "rồi", "roài": "rồi", "trc": "trước",
        "sd": "sử dụng", "h": "giờ", "bh": "bây giờ", "bjo": "bao giờ",
        "tbn": "thế mới nói", "th": "trường hợp", "chg": "chẳng",
        "qtqd": "quá trời quá đất",
        // --- Động từ / tính từ / trạng từ ---
        "ns": "nói", "nc": "nói chuyện", "bl": "bình luận", "cmt": "bình luận",
        "stt": "trạng thái", "tl": "trả lời", "rep": "trả lời", "nt": "nhắn tin",
        "ib": "nhắn tin riêng", "pm": "nhắn tin riêng",
        "wa": "quá", "qá": "quá", "nhìu": "nhiều", "nhiu": "nhiều", "mún": "muốn",
        "iu": "yêu", "thik": "thích", "thíc": "thích", "bt": "biết", "bth": "bình thường",
        "bik": "biết", "bit": "biết", "bjt": "biết", "bjk": "biết",
        "cũg": "cũng", "cg": "cũng", "cx": "cũng", "cug": "cũng", "lm": "làm",
        "zui": "vui", "zô": "vô", "gnn": "chúc ngủ ngon", "g9": "chúc ngủ ngon",
        "snvv": "sinh nhật vui vẻ",
        // --- Cảm thán / cười / thở dài ---
        "vl": "vờ lờ", "vc": "vãi cả", "vch": "vãi chưởng",
        "haha": "ha ha", "hihi": "hi hi", "huhu": "hu hu", "hic": "hức",
        "haizz": "hai za", "kkk": "kha kha kha", "mlem": "thèm quá",
        // --- Địa danh / thương hiệu / thông dụng ---
        "hcm": "Hồ Chí Minh", "hn": "Hà Nội", "sg": "Sài Gòn", "đn": "Đà Nẵng",
        "fb": "phây búc", "face": "phây búc", "ig": "in sờ ta gram", "insta": "in sờ ta gram",
        "yt": "diu túp", "tt": "tíc tóc", "zalo": "za lô", "đt": "điện thoại",
        "mt": "máy tính", "lt": "láp tóp", "sp": "sản phẩm", "shop": "cửa hàng",
        "sốp": "cửa hàng", "ad": "quản trị viên", "add": "kết bạn", "kb": "kết bạn",
        "kp": "kết bạn", "ship": "ship", "order": "đặt hàng", "sale": "giảm giá",
        "sub": "đăng ký", "dky": "đăng ký", "dnh": "đăng nhập", "like": "thích",
        "share": "chia sẻ", "live": "lai", "mxh": "mạng xã hội", "cđm": "cộng đồng mạng",
        "nsnd": "nghệ sĩ nhân dân", "drama": "đờ ra ma", "toxic": "tốc xích", "gg": "gu gồ",
        // --- Tiền / thời gian ---
        "đ": "đồng", "tr": "triệu", "củ": "triệu",
        // --- Cảm ơn / xin lỗi ---
        "tks": "cảm ơn", "thanks": "cảm ơn", "thx": "cảm ơn", "3q": "cảm ơn",
        "ty": "cảm ơn", "sr": "xin lỗi", "xl": "xin lỗi", "sorry": "xin lỗi",
        "plz": "làm ơn", "pls": "làm ơn",
        // --- Tài khoản / ngân hàng / công việc ---
        "acc": "ạc", "pass": "mật khẩu", "tk": "tài khoản", "qr": "quy rờ",
        "hack": "hake", "dchi": "địa chỉ", "ngh": "ngân hàng",
        "bks": "biển kiểm soát", "hđ": "hoạt động", "qd": "quyết định", "vb": "văn bản",
        "cq": "cơ quan", "cty": "công ty", "gd": "giám đốc", "pgd": "phó giám đốc",
        "pp": "phó phòng", "lh": "liên hệ", "nv": "nhân viên", "nn": "nhà nghỉ",
        "gv": "giáo viên", "hs": "học sinh", "sv": "sinh viên", "nvqs": "nghĩa vụ quân sự",
        "sll": "số lượng lớn", "fomo": "phô mô", "ot": "tăng ca", "bst": "bộ sưu tập",
        "sgbb": "sư gơ bây bi", "sgdd": "sư gơ đe đi",
        // --- Tiếng lóng có nghĩa (đọc rõ nghĩa) ---
        "gato": "ghen ăn tức ở",
        "trapboy": "kẻ lừa tình", "trapgirl": "kẻ lừa tình",
        "redflag": "cờ đỏ", "greenflag": "cờ xanh", "mukbang": "mấc banh",
        "vlog": "vê lốc", "checkvar": "chéc va", "quayxe": "quay xe",
        "etoet": "cứu với", "xinvia": "xin vía", "travia": "trả vía",
        "dinhchop": "đỉnh chóp", "xitkeo": "xịt keo", "phongbat": "phông bạt",
        "cmn": "chuẩn mẹ nó", "cmnr": "chuẩn mẹ nó rồi", "cmnl": "chuẩn mẹ nó luôn",
        "ccmnr": "chuẩn con mẹ nó rồi", "ccmnl": "chuẩn con mẹ nó luôn", "ncl": "nói chung là",
        // --- Meme / lóng đọc theo nghĩa vui (theo yêu cầu) ---
        "cc": "cục cưng", "dm": "định mệnh", "dcm": "định con mệnh", "tuất": "chó",
        // --- Từ tục có nguyên âm → đọc nhẹ / đánh vần (giữ live an toàn) ---
        "vloi": "vờ lờ", "vnoi": "vờ nờ", "vloz": "vờ lờ", "loz": "lờ", "eos": "không",
        "vaiz": "vãi", "vliz": "vãi", "vcliz": "vãi cả", "smliz": "sờ mờ lờ",
        "atcl": "ảo tưởng", "nguvl": "ngu vãi", "nguvkl": "ngu vãi", "nguvch": "ngu vãi chưởng",
        "atsm": "ảo tưởng sức mạnh", "atns": "ảo tưởng nhan sắc"
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

        // 0) Vài cụm có ký hiệu "/" (tokenizer sẽ tách) — xử lý trước.
        s = s.replacingOccurrences(of: "p/s", with: " tái bút ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "p.s", with: " tái bút ", options: .caseInsensitive)

        // 0b) Cụm nhiều từ (phải thay TRƯỚC khi tách từ). "hack mà gà" trước "hack ngu".
        if slang {
            let phrases: [(String, String)] = [
                ("hack mà gà", " không sao làm lại "),
                ("hack ngu", " anh chơi hay thế em hâm mộ anh ")
            ]
            for (k, v) in phrases {
                s = s.replacingOccurrences(of: k, with: v, options: .caseInsensitive)
            }
        }

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

        // 3) Thay từng "từ" theo từ điển tiếng lóng + ĐÁNH VẦN cụm viết tắt không đọc được
        //    (chỉ khi bật bộ lọc — dùng cho ElevenLabs & Chị Google).
        if slang { s = expandSlangAndSpell(s) }

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
        "km": "ki lô mét",
        "tp": "thành phố"
    ]

    /// CHỮ VIẾT KHÔNG DẤU → phục hồi dấu để đọc ĐÚNG CHÍNH TẢ.
    /// CHỈ chọn từ phổ biến & KHÔNG nhập nhằng (gần như luôn 1 nghĩa) để tránh đoán sai.
    /// Cố ý BỎ QUA các từ dễ nhầm (ban, toi, lam, cung, qua, moi, gia, do, dung, ngay…).
    static let noDiacritic: [String: String] = [
        "khong": "không", "duoc": "được", "nguoi": "người", "yeu": "yêu",
        "thich": "thích", "rat": "rất", "oi": "ơi", "minh": "mình",
        "chao": "chào", "dep": "đẹp", "gioi": "giỏi", "tuyet": "tuyệt",
        "roi": "rồi", "chua": "chưa", "biet": "biết", "hieu": "hiểu",
        "muon": "muốn", "thuong": "thương", "buon": "buồn", "khoc": "khóc",
        "cuoi": "cười", "uong": "uống", "com": "cơm", "nuoc": "nước",
        "tien": "tiền", "tot": "tốt", "xau": "xấu", "som": "sớm",
        "chieu": "chiều", "that": "thật", "vay": "vậy", "gi": "gì",
        "cuu": "cứu", "giup": "giúp", "luon": "luôn", "nhe": "nhé",
        // Bổ sung từ phổ biến (chọn nghĩa áp đảo trong văn nói/chat):
        "toi": "tôi", "ban": "bạn", "lam": "làm", "cung": "cũng", "gio": "giờ",
        "hom": "hôm", "noi": "nói", "di": "đi", "ve": "về", "den": "đến",
        "lai": "lại", "len": "lên", "xuong": "xuống", "vao": "vào", "cua": "của",
        "va": "và", "nhung": "nhưng", "neu": "nếu", "thi": "thì", "la": "là",
        "co": "có", "can": "cần", "phai": "phải", "nen": "nên", "ghet": "ghét",
        "chet": "chết", "hoc": "học", "lon": "lớn", "dai": "dài", "me": "mẹ",
        "ong": "ông", "troi": "trời", "met": "mệt", "khoe": "khỏe",
        "binh": "bình", "luan": "luận", "cam": "cảm", "ngheo": "nghèo"
    ]

    /// Tên chữ cái tiếng Việt để ĐÁNH VẦN rõ ràng (đọc "A" ra "a", "qr" ra "quy rờ")
    /// — KHÔNG đọc theo tiếng Anh. Dùng cho ElevenLabs & Google khi gặp cụm viết tắt.
    static let letterNames: [Character: String] = [
        "a": "a", "ă": "á", "â": "ớ", "b": "bờ", "c": "cờ", "d": "dờ", "đ": "đờ",
        "e": "e", "ê": "ê", "f": "phờ", "g": "gờ", "h": "hờ", "i": "i", "j": "gi",
        "k": "cờ", "l": "lờ", "m": "mờ", "n": "nờ", "o": "o", "ô": "ô", "ơ": "ơ",
        "p": "pờ", "q": "quy", "r": "rờ", "s": "sờ", "t": "tờ", "u": "u", "ư": "ư",
        "v": "vờ", "w": "vờ kép", "x": "xờ", "y": "i", "z": "dờ"
    ]

    // Nguyên âm tiếng Việt (đủ dấu) — để nhận biết cụm KHÔNG có nguyên âm (không đọc thành từ được).
    private static let vowelChars: Set<Character> =
        Set("aăâeêioôơuưyàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ")

    private static func hasVowel(_ token: String) -> Bool {
        for ch in token where vowelChars.contains(ch) { return true }
        return false
    }

    /// Đánh vần 1 cụm thành tên chữ cái tiếng Việt: "qr" → "quy rờ", "vcl" → "vờ cờ lờ".
    private static func spellLetters(_ token: String) -> String {
        var parts: [String] = []
        for ch in token {
            if let n = letterNames[ch] { parts.append(n) }
            else if ch.isNumber { parts.append(String(ch)) }
        }
        return parts.joined(separator: " ")
    }

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

    /// Như replaceWords(dictionary) nhưng có DỰ PHÒNG: cụm không có trong từ điển và
    /// KHÔNG có nguyên âm (vd "qr", "vcl", "sml", "dm") → đánh vần tên chữ cái tiếng Việt
    /// ("quy rờ", "vờ cờ lờ", "sờ mờ lờ", "dờ mờ"). Nhờ vậy đọc chữ cái rõ, không đọc tiếng Anh
    /// và tự làm nhẹ từ tục viết tắt trên live.
    private static func expandSlangAndSpell(_ text: String) -> String {
        var out = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            let key = token.lowercased()
            if let rep = dictionary[key] {
                out += rep
            } else if let rep = noDiacritic[key] {
                out += rep                        // phục hồi dấu chính tả (chữ không dấu phổ biến)
            } else if token.count >= 2 && token.count <= 6 && !token.contains(where: { $0.isNumber })
                        && !hasVowel(key) && letterNames.keys.contains(where: { key.contains($0) }) {
                out += spellLetters(key)          // cụm phụ âm thuần → đánh vần rõ ràng
            } else {
                out += token
            }
            token = ""
        }
        for ch in text {
            if ch.isLetter || ch.isNumber { token.append(ch) }
            else { flush(); out.append(ch) }
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
