import SwiftUI
import AVFoundation

// ======================== Giọng đọc nâng cao (FILE MỚI — không sửa TTSView cũ) ========================
// Hỗ trợ: giọng máy offline (mọi ngôn ngữ) + giọng Google online (chị Google, nhiều thứ tiếng, miễn phí).

final class SysVoiceEngine: ObservableObject {
    let synth = AVSpeechSynthesizer()
    func speak(_ text: String, voiceId: String, rate: Float, pitch: Float) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        if !voiceId.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceId) { u.voice = v }
        u.rate = rate
        u.pitchMultiplier = pitch
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate) }
}

final class GoogleVoiceEngine: ObservableObject {
    private var player: AVQueuePlayer?
    private var currentSpeed: Float = 1.0   // tốc độ phát đang dùng (giữ để đổi NGAY khi kéo thanh)

    func play(_ text: String, lang: String, speed: Float = 1.0) {
        stop()
        currentSpeed = speed
        let items = Self.chunk(text).compactMap { c -> AVPlayerItem? in
            Self.url(c, lang).map { url -> AVPlayerItem in
                let it = AVPlayerItem(url: url)
                // Giữ cao độ giọng khi đổi tốc độ (timeDomain hợp với giọng nói) → không bị méo/the thé.
                it.audioTimePitchAlgorithm = .timeDomain
                return it
            }
        }
        guard !items.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVQueuePlayer(items: items)
        player = p
        // Đặt rate = tốc độ chọn → vừa bắt đầu phát vừa áp đúng tốc độ.
        p.rate = speed
    }

    /// Đổi tốc độ NGAY cho đoạn đang phát (kéo thanh là nghe đổi liền, không cần đọc lại).
    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        guard let p = player, p.rate != 0 else { return }   // chỉ đổi khi đang phát (không tự bật khi đang dừng)
        p.rate = speed
    }
    func stop() { player?.pause(); player = nil }

    static func url(_ text: String, _ lang: String) -> URL? {
        let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=\(lang)&q=\(q)")
    }
    // Google giới hạn ~200 ký tự/lần → cắt theo từ
    static func chunk(_ s: String, maxLen: Int = 180) -> [String] {
        var out: [String] = []; var cur = ""
        for w in s.split(separator: " ") {
            if cur.count + w.count + 1 > maxLen {
                if !cur.isEmpty { out.append(cur) }
                cur = String(w)
            } else {
                cur += (cur.isEmpty ? "" : " ") + w
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.isEmpty ? [s] : out
    }
}

struct NewVoiceTTSView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var sys = SysVoiceEngine()
    @StateObject private var ggl = GoogleVoiceEngine()

    @State private var text = "Xin chào, đây là giọng đọc của KENIOS."
    @State private var source = 1            // 0 máy offline, 1 Google online
    @State private var rate: Float = 0.5
    @State private var pitch: Float = 1.0
    @State private var voiceId = ""
    @State private var lang = "vi"
    @State private var downloadURL: URL?
    @State private var info: String?

    // Map thanh rate (0…1, mặc định 0.5) → bội số tốc độ Google 0.5x…2.0x (0.5 = 1.0x bình thường).
    private var googleSpeed: Float { max(0.5, min(2.0, rate * 2.0)) }

    private let langs: [(String, String)] = [
        ("vi", "Tiếng Việt 🇻🇳"), ("en", "English 🇬🇧"), ("ja", "日本語 🇯🇵"),
        ("ko", "한국어 🇰🇷"), ("zh-CN", "中文 🇨🇳"), ("fr", "Français 🇫🇷"),
        ("es", "Español 🇪🇸"), ("th", "ไทย 🇹🇭"), ("ru", "Русский 🇷🇺"),
        ("de", "Deutsch 🇩🇪"), ("hi", "हिन्दी 🇮🇳"), ("id", "Indonesia 🇮🇩"),
    ]

    private var sysVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { $0.language < $1.language }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Nội dung").font(.subheadline.bold())
                TextEditor(text: $text)
                    .frame(minHeight: 120).padding(8).kCard(12)

                Picker("Nguồn giọng", selection: $source) {
                    Text("Giọng máy (offline)").tag(0)
                    Text("Giọng Google (online)").tag(1)
                }.pickerStyle(.segmented)

                // Free chỉ dùng giọng máy; Google online (voice-id) cần Pro
                if source == 1 && !store.isPro {
                    ProLockCard(feature: "Giọng Google online (voice-id)")
                } else if source == 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chọn giọng (\(sysVoices.count) giọng có sẵn)").font(.caption).foregroundStyle(.secondary)
                        Picker("Giọng", selection: $voiceId) {
                            Text("Mặc định").tag("")
                            ForEach(sysVoices, id: \.identifier) { v in
                                Text("\(v.name) · \(v.language)").tag(v.identifier)
                            }
                        }.pickerStyle(.menu)
                        HStack { Text("Tốc độ"); Spacer(); Text(String(format: "%.2f", rate)) }.font(.caption)
                        Slider(value: $rate, in: 0.0...1.0)
                        HStack { Text("Cao độ"); Spacer(); Text(String(format: "%.2f", pitch)) }.font(.caption)
                        Slider(value: $pitch, in: 0.5...2.0)
                    }.padding().kCard(14)

                    HStack {
                        Button { sys.speak(text, voiceId: voiceId, rate: rate, pitch: pitch) } label: {
                            Label("Đọc", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { sys.stop() } label: {
                            Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ngôn ngữ (giọng Google cập nhật online)").font(.caption).foregroundStyle(.secondary)
                        Picker("Ngôn ngữ", selection: $lang) {
                            ForEach(langs, id: \.0) { Text($0.1).tag($0.0) }
                        }.pickerStyle(.menu)
                        HStack { Text("Tốc độ"); Spacer(); Text(String(format: "%.2fx", googleSpeed)) }.font(.caption)
                        Slider(value: $rate, in: 0.0...1.0)
                            .onChange(of: rate) { _ in ggl.setSpeed(googleSpeed) }
                        Text("Giọng Google đọc hay & tự nhiên hơn, cần có mạng. Tự cắt đoạn để đọc văn bản dài. Kéo thanh tốc độ để chỉnh nhanh/chậm.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }.padding().kCard(14)

                    HStack {
                        Button { ggl.play(text, lang: lang, speed: googleSpeed) } label: {
                            Label("Đọc", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                        Button { ggl.stop() } label: {
                            Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                    }

                    Button { Task { await downloadMP3() } } label: {
                        Label("Tải MP3 (đoạn đầu)", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    if let downloadURL {
                        ShareLink(item: downloadURL) {
                            Label("Chia sẻ / lưu file MP3", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                if let info { Text(info).font(.caption).foregroundStyle(.green) }
            }
            .padding()
        }
        .navigationTitle("Giọng đọc nâng cao")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { sys.stop(); ggl.stop() }
    }

    private func downloadMP3() async {
        info = nil; downloadURL = nil
        let first = GoogleVoiceEngine.chunk(text).first ?? text
        guard let url = GoogleVoiceEngine.url(first, lang) else { return }
        do {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("kenios_voice_\(Int(Date().timeIntervalSince1970)).mp3")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: tmp, to: dest)
            downloadURL = dest
            info = "Đã tải MP3 (đoạn đầu)."
        } catch {
            info = "Tải MP3 thất bại: \(error.localizedDescription)"
        }
    }
}
