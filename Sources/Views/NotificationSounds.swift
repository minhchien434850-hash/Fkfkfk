import Foundation
import AVFoundation

// ============================================================================
//  ÂM THANH THÔNG BÁO (giống TikFinity) — tổng hợp tại chỗ, 100% cục bộ.
//  KHÔNG cần file mp3 đính kèm (tránh phình app & rắc rối ESign). Mỗi âm là một
//  chuỗi nốt (tần số + thời lượng) được dựng thành WAV PCM rồi phát bằng AVAudioPlayer.
// ============================================================================

struct NotifSoundPreset: Identifiable {
    let id: String
    let label: String
    let icon: String
    /// Chuỗi nốt: (tần số Hz, thời lượng giây). Tần số 0 = khoảng lặng.
    let segments: [(Double, Double)]
}

// Danh sách âm thanh chọn được (trên 20 lựa chọn) — người dùng gán cho từng loại sự kiện.
let kNotifSounds: [NotifSoundPreset] = [
    .init(id: "none",     label: "Không có",   icon: "speaker.slash.fill",            segments: []),
    .init(id: "custom",   label: "Tùy chỉnh",  icon: "link",                          segments: []),
    .init(id: "ding",     label: "Ding",       icon: "bell.fill",                     segments: [(880, 0.26)]),
    .init(id: "dingdong", label: "Ding Dong",  icon: "bell.badge.fill",               segments: [(659, 0.16), (880, 0.24)]),
    .init(id: "coin",     label: "Xu",         icon: "dollarsign.circle.fill",        segments: [(988, 0.09), (1319, 0.26)]),
    .init(id: "chime",    label: "Chuông",     icon: "sparkles",                      segments: [(523, 0.12), (659, 0.12), (784, 0.22)]),
    .init(id: "pop",      label: "Pop",        icon: "circle.fill",                   segments: [(1200, 0.08)]),
    .init(id: "alert",    label: "Báo động",   icon: "exclamationmark.triangle.fill", segments: [(1000, 0.1), (0, 0.05), (1000, 0.1), (0, 0.05), (1000, 0.12)]),
    .init(id: "bell",     label: "Chuông ngân",icon: "bell.circle.fill",              segments: [(1568, 0.42)]),
    .init(id: "tada",     label: "Ta-da",      icon: "party.popper.fill",             segments: [(587, 0.1), (587, 0.1), (784, 0.3)]),
    .init(id: "heart",    label: "Tim",        icon: "heart.fill",                    segments: [(880, 0.1), (1175, 0.2)]),
    .init(id: "level",    label: "Lên cấp",    icon: "arrow.up.circle.fill",          segments: [(523, 0.08), (659, 0.08), (784, 0.08), (1047, 0.22)]),
    .init(id: "knock",    label: "Gõ cửa",     icon: "hand.tap.fill",                 segments: [(300, 0.06), (0, 0.07), (300, 0.06)]),
    .init(id: "twinkle",  label: "Lấp lánh",   icon: "star.fill",                     segments: [(1047, 0.07), (1319, 0.07), (1568, 0.07), (2093, 0.16)]),
    .init(id: "boop",     label: "Boop",       icon: "circle.grid.cross.fill",        segments: [(440, 0.09), (392, 0.14)]),
    .init(id: "laser",    label: "Laser",      icon: "bolt.fill",                     segments: [(1800, 0.05), (1400, 0.05), (1000, 0.05), (600, 0.12)]),
    .init(id: "success",  label: "Thành công", icon: "checkmark.seal.fill",           segments: [(784, 0.1), (1047, 0.1), (1319, 0.22)]),
    .init(id: "fanfare",  label: "Kèn vui",    icon: "megaphone.fill",                segments: [(523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.1), (784, 0.1), (1047, 0.26)]),
    .init(id: "drop",     label: "Giọt nước",  icon: "drop.fill",                     segments: [(1500, 0.05), (700, 0.18)]),
    .init(id: "whistle",  label: "Huýt sáo",   icon: "wind",                          segments: [(1200, 0.08), (1600, 0.08), (2000, 0.18)]),
    .init(id: "arcade",   label: "Game cổ",    icon: "gamecontroller.fill",           segments: [(659, 0.07), (988, 0.07), (1319, 0.07), (988, 0.07), (1319, 0.18)]),
    .init(id: "magic",    label: "Phép thuật", icon: "wand.and.stars",                segments: [(784, 0.06), (1047, 0.06), (1319, 0.06), (1760, 0.06), (2349, 0.18)]),
    .init(id: "gong",     label: "Cồng",       icon: "circle.hexagongrid.fill",       segments: [(196, 0.5)]),
    .init(id: "buzz",     label: "Rè",         icon: "waveform",                      segments: [(220, 0.18)]),
    .init(id: "trumpet",  label: "Vinh danh",  icon: "crown.fill",                    segments: [(523, 0.12), (659, 0.12), (784, 0.34)]),
    .init(id: "bubble",   label: "Bong bóng",  icon: "bubble.left.fill",              segments: [(600, 0.05), (900, 0.05), (1200, 0.12)]),
    .init(id: "siren",    label: "Còi hú",     icon: "light.beacon.max.fill",         segments: [(700, 0.14), (1000, 0.14), (700, 0.14), (1000, 0.14)]),
    .init(id: "applause", label: "Vỗ tay",     icon: "hands.clap.fill",               segments: [(1000, 0.04), (0, 0.03), (1200, 0.04), (0, 0.03), (900, 0.04), (0, 0.03), (1100, 0.1)]),
    .init(id: "doorbell", label: "Chuông cửa", icon: "house.fill",                    segments: [(784, 0.2), (0, 0.05), (587, 0.3)]),
    .init(id: "ufo",      label: "Đĩa bay",    icon: "airpodspro",                    segments: [(400, 0.08), (800, 0.08), (1200, 0.08), (1600, 0.08), (1200, 0.16)]),
    .init(id: "softbell", label: "Chuông êm",  icon: "moon.stars.fill",               segments: [(1319, 0.1), (1047, 0.3)]),
    .init(id: "chirp",    label: "Chim hót",   icon: "bird.fill",                     segments: [(2000, 0.05), (2500, 0.05), (2000, 0.05)]),
    .init(id: "zap",      label: "Zap",        icon: "bolt.horizontal.fill",          segments: [(2000, 0.04), (500, 0.12)]),
    .init(id: "ping",     label: "Ping",       icon: "dot.radiowaves.right",          segments: [(1760, 0.18)]),
    .init(id: "plop",     label: "Plop",       icon: "drop.circle.fill",              segments: [(500, 0.06), (300, 0.1)]),
    .init(id: "ascend",   label: "Đi lên",     icon: "arrow.up.forward.circle.fill",  segments: [(440, 0.07), (554, 0.07), (659, 0.07), (880, 0.18)]),
    .init(id: "descend",  label: "Đi xuống",   icon: "arrow.down.forward.circle.fill",segments: [(880, 0.07), (659, 0.07), (554, 0.07), (440, 0.18)]),
    .init(id: "victory",  label: "Chiến thắng",icon: "trophy.fill",                   segments: [(523, 0.12), (523, 0.12), (523, 0.12), (659, 0.3)]),
    .init(id: "coin2",    label: "Xu 2",       icon: "centsign.circle.fill",          segments: [(1319, 0.08), (1568, 0.22)]),
    .init(id: "blip",     label: "Blip",       icon: "smallcircle.filled.circle.fill",segments: [(1500, 0.06)]),
    .init(id: "marimba",  label: "Marimba",    icon: "music.note",                    segments: [(784, 0.1), (1047, 0.1), (1319, 0.2)]),
    .init(id: "harp",     label: "Đàn hạc",    icon: "music.note.list",               segments: [(523, 0.06), (659, 0.06), (784, 0.06), (1047, 0.06), (1319, 0.18)]),
    .init(id: "beepbeep", label: "Bíp bíp",    icon: "antenna.radiowaves.left.and.right", segments: [(1000, 0.08), (0, 0.05), (1000, 0.08)]),
    .init(id: "powerup",  label: "Tăng lực",   icon: "bolt.circle.fill",              segments: [(392, 0.05), (523, 0.05), (659, 0.05), (784, 0.05), (1047, 0.15)]),
    .init(id: "notify",   label: "Thông báo",  icon: "bell.badge",                    segments: [(1175, 0.1), (1568, 0.2)]),
    .init(id: "glass",    label: "Ly thủy tinh",icon: "cup.and.saucer.fill",          segments: [(2093, 0.3)]),
    .init(id: "wood",     label: "Gõ gỗ",      icon: "leaf.fill",                     segments: [(800, 0.05), (0, 0.04), (600, 0.08)]),
    .init(id: "cuckoo",   label: "Cu cu",      icon: "bird.circle.fill",              segments: [(784, 0.15), (622, 0.2)]),
    .init(id: "fairy",    label: "Tiên",       icon: "wand.and.rays",                 segments: [(1568, 0.05), (2093, 0.05), (2637, 0.05), (3136, 0.14)]),
    .init(id: "robot",    label: "Người máy",  icon: "cpu",                           segments: [(440, 0.06), (330, 0.06), (440, 0.06), (330, 0.12)]),
    .init(id: "alarm2",   label: "Báo thức",   icon: "alarm.fill",                    segments: [(880, 0.12), (0, 0.05), (880, 0.12), (0, 0.05), (880, 0.12)]),
    .init(id: "trill",    label: "Luyến láy",  icon: "waveform.path",                 segments: [(1047, 0.04), (1175, 0.04), (1047, 0.04), (1175, 0.04), (1047, 0.12)]),
    .init(id: "splash",   label: "Tõm",        icon: "drop.fill",                     segments: [(1800, 0.04), (1200, 0.04), (600, 0.14)]),
    .init(id: "horn",     label: "Còi xe",     icon: "megaphone",                     segments: [(330, 0.3)]),
    .init(id: "kalimba",  label: "Kalimba",    icon: "pianokeys",                     segments: [(659, 0.1), (988, 0.1), (1319, 0.22)]),
    .init(id: "bellrun",  label: "Chuông chạy",icon: "bell.badge.fill",               segments: [(1047, 0.06), (1319, 0.06), (1568, 0.06), (2093, 0.06), (1568, 0.16)]),
    .init(id: "click2",   label: "Tách tách",  icon: "cursorarrow.click",             segments: [(1500, 0.03), (0, 0.03), (1500, 0.03)]),
    .init(id: "swoosh",   label: "Vút",        icon: "wind",                          segments: [(2000, 0.05), (1500, 0.05), (1000, 0.05), (500, 0.1)]),
    .init(id: "ding3",    label: "Ding 3",     icon: "bell.fill",                     segments: [(1047, 0.08), (1319, 0.08), (1568, 0.2)]),
    .init(id: "celebrate",label: "Ăn mừng",    icon: "party.popper",                  segments: [(784, 0.08), (988, 0.08), (1319, 0.08), (1568, 0.24)]),
    .init(id: "softpop",  label: "Pop êm",     icon: "circle",                        segments: [(900, 0.07)]),
    .init(id: "deepbell", label: "Chuông trầm",icon: "bell.circle",                   segments: [(262, 0.45)]),
    .init(id: "phone",    label: "Điện thoại", icon: "phone.fill",                    segments: [(1209, 0.1), (1336, 0.1), (1209, 0.1), (1336, 0.1)]),
    .init(id: "win",      label: "Thắng lớn",  icon: "rosette",                       segments: [(659, 0.1), (784, 0.1), (988, 0.1), (1319, 0.26)]),
    .init(id: "sparkle3", label: "Lung linh",  icon: "sparkle",                       segments: [(2637, 0.05), (3136, 0.05), (2637, 0.05), (3520, 0.14)]),
    .init(id: "boom",     label: "Bùm",        icon: "burst.fill",                    segments: [(120, 0.3)]),
    .init(id: "tick",     label: "Tích",       icon: "metronome.fill",                segments: [(1800, 0.03)]),
    .init(id: "gift2",    label: "Quà 2",      icon: "shippingbox.fill",              segments: [(880, 0.08), (1047, 0.08), (1319, 0.08), (1047, 0.18)]),
    .init(id: "rise",     label: "Vươn cao",   icon: "chart.line.uptrend.xyaxis",     segments: [(440, 0.04), (587, 0.04), (740, 0.04), (880, 0.04), (1175, 0.16)]),
    .init(id: "twobell",  label: "Hai chuông", icon: "bell.and.waves.left.and.right.fill", segments: [(1319, 0.14), (0, 0.05), (1319, 0.22)]),
]

enum NotifSoundSynth {
    static let sampleRate: Double = 44100

    /// Dựng WAV PCM 16-bit mono từ chuỗi nốt, có bao biên (attack/decay) để không bị "tách".
    static func makeWAV(_ segments: [(Double, Double)]) -> Data? {
        guard !segments.isEmpty else { return nil }
        var samples: [Int16] = []
        for (freq, dur) in segments {
            let count = max(1, Int(dur * sampleRate))
            for i in 0..<count {
                let t = Double(i) / sampleRate
                var amp = 0.0
                if freq > 0 {
                    let attack = 0.008
                    let a = t < attack ? t / attack : 1.0                 // lên nhanh
                    let remain = dur - t
                    let release = remain < 0.012 ? max(0, remain / 0.012) : 1.0 // tắt êm cuối nốt
                    let decay = exp(-3.0 * t / dur)                        // ngân giảm dần
                    amp = sin(2.0 * Double.pi * freq * t) * a * release * decay * 0.6
                }
                samples.append(Int16(max(-1.0, min(1.0, amp)) * 32767))
            }
        }
        return wavData(samples)
    }

    private static func wavData(_ samples: [Int16]) -> Data {
        let channels: Int16 = 1
        let bps: Int16 = 16
        let sr = Int32(sampleRate)
        let byteRate = sr * Int32(channels) * Int32(bps / 8)
        let blockAlign = channels * (bps / 8)
        let dataSize = Int32(samples.count) * Int32(bps / 8)

        var d = Data()
        d.append(contentsOf: "RIFF".utf8)
        var total = (dataSize + 36).littleEndian; d.append(Data(bytes: &total, count: 4))
        d.append(contentsOf: "WAVEfmt ".utf8)
        var fmtSize: Int32 = 16; d.append(Data(bytes: &fmtSize, count: 4))
        var format: Int16 = 1; d.append(Data(bytes: &format, count: 2))         // PCM
        var ch = channels.littleEndian; d.append(Data(bytes: &ch, count: 2))
        var srLE = sr.littleEndian; d.append(Data(bytes: &srLE, count: 4))
        var brLE = byteRate.littleEndian; d.append(Data(bytes: &brLE, count: 4))
        var baLE = blockAlign.littleEndian; d.append(Data(bytes: &baLE, count: 2))
        var bpsLE = bps.littleEndian; d.append(Data(bytes: &bpsLE, count: 2))
        d.append(contentsOf: "data".utf8)
        var dsLE = dataSize.littleEndian; d.append(Data(bytes: &dsLE, count: 4))
        for s in samples { var le = s.littleEndian; d.append(Data(bytes: &le, count: 2)) }
        return d
    }
}
