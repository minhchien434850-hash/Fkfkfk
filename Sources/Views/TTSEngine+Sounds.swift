import AVFoundation

// ======================== Âm thanh thông báo (tặng quà · follow · chia sẻ) ========================
extension TTSEngine {

    // Loại sự kiện có gắn âm thanh thông báo (đúng 3 cái người dùng yêu cầu).
    static let notifEventTypes = ["gift", "follow", "share"]

    // Âm mặc định cho từng loại (người dùng đổi được trong cài đặt).
    func defaultNotifSound(for type: String) -> String {
        switch type {
        case "gift":   return "coin"
        case "follow": return "heart"
        case "share":  return "chime"
        default:       return "none"
        }
    }

    func notifSoundId(for type: String) -> String {
        UserDefaults.standard.string(forKey: "tts_sound_\(type)") ?? defaultNotifSound(for: type)
    }
    func setNotifSound(_ id: String, for type: String) {
        UserDefaults.standard.set(id, forKey: "tts_sound_\(type)")
        objectWillChange.send()
    }

    /// Phát âm thanh thông báo cho loại sự kiện rồi GỌI `then` (đọc text). Nếu không có âm → đọc ngay.
    func playNotif(for type: String, then: @escaping () -> Void) {
        let sid = notifSoundId(for: type)
        guard let preset = kNotifSounds.first(where: { $0.id == sid }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else {
            then(); return
        }
        activateSession()
        do {
            let p = try AVAudioPlayer(data: data)
            p.volume = volume
            p.prepareToPlay()
            let dur = p.duration
            p.play()
            notifPlayer = p
            // Đọc NGAY SAU khi âm thanh phát xong (đúng yêu cầu: âm trước, đọc sau).
            DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.05) { then() }
        } catch {
            then()
        }
    }

    /// Nghe thử 1 âm thanh (dùng cho màn chọn âm).
    func previewNotifSound(_ id: String) {
        guard let preset = kNotifSounds.first(where: { $0.id == id }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else { return }
        activateSession()
        if let p = try? AVAudioPlayer(data: data) {
            p.volume = volume
            p.prepareToPlay()
            p.play()
            notifPlayer = p
        }
    }

    /// Thông báo 1 sự kiện: phát âm thanh (nếu là gift/follow/share) TRƯỚC rồi mới đọc.
    func announce(_ text: String, eventType: String) {
        activateSession()
        if silentPlayer == nil { startBackgroundMode() }
        if Self.notifEventTypes.contains(eventType) {
            playNotif(for: eventType) { [weak self] in self?.speak(text) }
        } else {
            speak(text)
        }
    }
}
