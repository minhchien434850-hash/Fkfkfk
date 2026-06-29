import SwiftUI

// ======================== Mô hình dùng chung cho TTS ========================
// Tách riêng để TTSView gọn hơn, dễ kiểm soát.

// ----- Loại sự kiện livestream -----
struct LiveEventType: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let template: String     // dùng {name} và {content}
}

let kLiveEvents: [LiveEventType] = [
    .init(id: "join",    label: "Người vào",   icon: "person.fill.badge.plus", template: "Chào mừng {name} đã vào phòng"),
    .init(id: "gift",    label: "Tặng quà",    icon: "gift.fill",              template: "Cảm ơn {name} đã tặng {content}"),
    .init(id: "comment", label: "Bình luận",   icon: "text.bubble.fill",       template: "{name} bình luận: {content}"),
    .init(id: "follow",  label: "Follow",      icon: "heart.fill",             template: "Cảm ơn {name} đã theo dõi"),
    .init(id: "share",   label: "Chia sẻ",     icon: "square.and.arrow.up.fill", template: "Cảm ơn {name} đã chia sẻ live"),
]

// ----- Kiểu giọng (preset cao độ / tốc độ) -----
struct VoiceStyle: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let pitch: Float
    let rate: Float
}

let kVoiceStyles: [VoiceStyle] = [
    .init(id: "normal",   label: "Thường",    icon: "person.wave.2",        pitch: 1.0,  rate: 0.50),
    .init(id: "anime_f",  label: "Anime nữ",  icon: "sparkles",             pitch: 1.7,  rate: 0.54),
    .init(id: "anime_m",  label: "Anime nam", icon: "bolt.fill",            pitch: 0.75, rate: 0.52),
    .init(id: "child",    label: "Trẻ em",    icon: "figure.child",         pitch: 1.9,  rate: 0.50),
    .init(id: "warm",     label: "Trầm ấm",   icon: "moon.zzz.fill",        pitch: 0.82, rate: 0.46),
    .init(id: "fast",     label: "Nhanh",     icon: "hare.fill",            pitch: 1.05, rate: 0.60),
    .init(id: "slow",     label: "Chậm rõ",   icon: "tortoise.fill",        pitch: 1.0,  rate: 0.40),
    .init(id: "robot",    label: "Robot",     icon: "cpu",                  pitch: 0.6,  rate: 0.48),
    // Preset trầm tự nhiên: pitch thấp, tốc độ vừa
    .init(id: "tiktok_deep", label: "Trầm TikTok", icon: "music.note.tv.fill", pitch: 0.80, rate: 0.52),
]

// ----- Preset tông giọng ElevenLabs -----
struct ElevenTonePreset: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
    let stability: Double       // 0.0 (phong phú/linh hoạt) → 1.0 (ổn định/đơ)
    let similarityBoost: Double // 0.0 → 1.0 (bám sát giọng gốc)
    let style: Double           // 0.0 → 1.0 (cảm xúc/ngữ điệu)
    let speakerBoost: Bool
}

let kElevenTonePresets: [ElevenTonePreset] = [
    // Xu hướng TikTok — giọng đọc bình luận live điển hình
    .init(id: "tiktok_calm",   label: "TikTok Nhẹ",   icon: "music.note.tv.fill",
          stability: 0.50, similarityBoost: 0.85, style: 0.25, speakerBoost: true),
    .init(id: "tiktok_hype",   label: "TikTok Hype",  icon: "bolt.fill",
          stability: 0.28, similarityBoost: 0.88, style: 0.65, speakerBoost: true),
    .init(id: "tiktok_deep",   label: "Trầm sâu",     icon: "waveform.path.ecg",
          stability: 0.60, similarityBoost: 0.92, style: 0.10, speakerBoost: true),
    .init(id: "tiktok_warm",   label: "Ấm áp",        icon: "moon.zzz.fill",
          stability: 0.55, similarityBoost: 0.80, style: 0.35, speakerBoost: true),
    .init(id: "tiktok_clear",  label: "Rõ ràng",      icon: "speaker.wave.3.fill",
          stability: 0.72, similarityBoost: 0.95, style: 0.05, speakerBoost: true),
    .init(id: "tiktok_emote",  label: "Cảm xúc",      icon: "heart.fill",
          stability: 0.22, similarityBoost: 0.82, style: 0.80, speakerBoost: true),
]
