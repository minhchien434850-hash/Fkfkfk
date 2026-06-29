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

    // Link âm thanh tự dán (meme cười, la hét, airhorn…) cho từng sự kiện khi chọn "Tùy chỉnh".
    func notifSoundUrl(for type: String) -> String {
        UserDefaults.standard.string(forKey: "tts_sound_url_\(type)") ?? ""
    }
    func setNotifSoundUrl(_ url: String, for type: String) {
        UserDefaults.standard.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "tts_sound_url_\(type)")
        objectWillChange.send()
    }

    // Tải (và cache) audio từ link mp3/wav để phát làm âm thông báo.
    func fetchNotifData(_ url: URL, completion: @escaping (Data?) -> Void) {
        let key = url.absoluteString
        if let cached = notifDataCache[key] { completion(cached); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                if let data, (code == 200 || code == 0), data.count > 200 {
                    self?.notifDataCache[key] = data
                    completion(data)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }

    // Phát 1 đoạn audio đã có Data, rồi gọi `then` khi phát xong (then = nil nếu chỉ nghe thử).
    func playNotifData(_ data: Data, then: (() -> Void)? = nil) {
        activateSession()
        do {
            let p = try AVAudioPlayer(data: data)
            p.volume = volume
            p.prepareToPlay()
            let dur = p.duration
            p.play()
            notifPlayer = p
            if let then { DispatchQueue.main.asyncAfter(deadline: .now() + dur + 0.05) { then() } }
        } catch {
            then?()
        }
    }

    /// Phát âm thanh thông báo cho loại sự kiện rồi GỌI `then` (đọc text). Nếu không có âm → đọc ngay.
    func playNotif(for type: String, then: @escaping () -> Void) {
        let sid = notifSoundId(for: type)
        if sid == "none" { then(); return }
        // Âm tùy chỉnh: tải từ link người dùng dán (meme cười/la hét…) rồi phát trước, đọc sau.
        if sid == "custom" {
            let s = notifSoundUrl(for: type)
            guard !s.isEmpty, let url = URL(string: s) else { then(); return }
            fetchNotifData(url) { [weak self] data in
                guard let self, let data else { then(); return }
                self.playNotifData(data) { then() }
            }
            return
        }
        guard let preset = kNotifSounds.first(where: { $0.id == sid }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else {
            then(); return
        }
        playNotifData(data) { then() }
    }

    /// Nghe thử 1 âm TỔNG HỢP theo id (dùng khi chạm chip).
    func previewNotifSound(_ id: String) {
        guard let preset = kNotifSounds.first(where: { $0.id == id }),
              let data = NotifSoundSynth.makeWAV(preset.segments) else { return }
        playNotifData(data, then: nil)
    }

    /// Nghe thử đúng âm ĐANG CHỌN của 1 sự kiện (xử lý cả "custom" theo link).
    func previewNotif(for type: String) {
        let sid = notifSoundId(for: type)
        if sid == "custom" {
            let s = notifSoundUrl(for: type)
            guard !s.isEmpty, let url = URL(string: s) else { return }
            fetchNotifData(url) { [weak self] data in
                guard let self, let data else { return }
                self.playNotifData(data, then: nil)
            }
        } else if sid != "none" {
            previewNotifSound(sid)
        }
    }

    // ===== Kho âm tùy chỉnh (KHÔNG giới hạn số lượng) =====
    func customSounds() -> [[String: String]] {
        guard let raw = UserDefaults.standard.string(forKey: "tts_custom_sounds"),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return arr
    }
    func saveCustomSounds(_ list: [[String: String]]) {
        if let data = try? JSONSerialization.data(withJSONObject: list),
           let s = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(s, forKey: "tts_custom_sounds")
            objectWillChange.send()
        }
    }
    func addCustomSound(url: String, name: String = "") {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        var list = customSounds()
        if list.contains(where: { $0["url"] == u }) { return }   // bỏ trùng
        let nm = name.isEmpty ? ((URL(string: u)?.lastPathComponent).map { String($0.prefix(18)) } ?? "Âm") : name
        list.append(["url": u, "name": nm])
        saveCustomSounds(list)
    }
    func removeCustomSound(url: String) {
        var list = customSounds()
        list.removeAll { $0["url"] == url }
        saveCustomSounds(list)
    }
    // Yêu cầu giao diện vẽ lại sau khi kho âm dùng chung được tải từ máy chủ.
    func reloadNotif() { objectWillChange.send() }

    // Nghe thử 1 link bất kỳ (kho tùy chỉnh).
    func previewCustomUrl(_ s: String) {
        guard let url = URL(string: s), !s.isEmpty else { return }
        fetchNotifData(url) { [weak self] data in
            guard let self, let data else { return }
            self.playNotifData(data, then: nil)
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
