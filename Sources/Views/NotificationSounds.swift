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
