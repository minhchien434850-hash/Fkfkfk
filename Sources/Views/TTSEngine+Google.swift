import AVFoundation

// ======================== Chị Google (online, prefetch để hết khoảng lặng) ========================
extension TTSEngine {

    func playGoogleTTS(_ text: String, level: Int = TTSEngine.SpeakPriority.comment.rawValue) {
        // Google TTS giới hạn ~200 ký tự/yêu cầu → chia 180 và đọc lần lượt TOÀN BỘ.
        let chunks = splitTextIntoChunks(text, maxLen: 180)
        guard !chunks.isEmpty else { return }

        // Người vào phòng (mức thấp nhất): khi live đông, hàng loạt lời chào dồn về sẽ nghẽn
        // hàng đợi và làm bình luận đọc chậm. → Chỉ giữ tối đa `maxJoinBacklog` lời chào chờ đọc,
        // bỏ bớt lời chào CŨ nhất để welcome luôn mới và không chặn bình luận.
        if level == TTSEngine.SpeakPriority.join.rawValue {
            trimGoogleJoinBacklog()
        }

        // Chèn theo mức ưu tiên: quà/follow/share > bình luận > người vào.
        // Bình luận LUÔN chèn TRƯỚC các lời chào "người vào" đang chờ.
        let idx = queueInsertIndex(googlePrio, level: level)
        googleQueue.insert(contentsOf: chunks, at: idx)
        googlePrio.insert(contentsOf: Array(repeating: level, count: chunks.count), at: idx)
        // Nếu chèn lên ĐẦU hàng đợi → audio prefetch của đoạn đầu cũ không còn đúng → bỏ để tải lại.
        if idx == 0 { googleNextData = nil }

        pendingCount = googleQueue.count + elevenQueue.count
        if !isPlayingGoogle {
            playNextGoogleItem()
        }
    }

    // Bỏ bớt lời chào "người vào" CŨ nhất khi đang tồn đọng quá nhiều.
    private func trimGoogleJoinBacklog() {
        let joinLevel = TTSEngine.SpeakPriority.join.rawValue
        while googlePrio.filter({ $0 == joinLevel }).count >= maxJoinBacklog,
              let first = googlePrio.firstIndex(of: joinLevel) {
            googleQueue.remove(at: first)
            googlePrio.remove(at: first)
            if first == 0 { googleNextData = nil }   // đã bỏ đoạn đầu → prefetch cũ không còn đúng
        }
        pendingCount = googleQueue.count + elevenQueue.count
    }

    // Chia đoạn THÔNG MINH: GIỮ trọn câu (tách theo . ? ! ; xuống dòng) rồi GỘP các câu
    // lại tới gần maxLen. Ít đoạn hơn → ít khoảng lặng giữa các đoạn → đọc mượt, rõ hơn.
    func splitTextIntoChunks(_ text: String, maxLen: Int) -> [String] {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        // Tách thành các câu trọn vẹn (giữ lại dấu kết câu).
        var sentences: [String] = []
        var cur = ""
        for ch in flat {
            cur.append(ch)
            if ".?!;".contains(ch) {
                let s = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { sentences.append(s) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }

        // Gộp câu tới maxLen; câu nào quá dài thì cắt theo từ.
        var chunks: [String] = []
        var buf = ""
        func flush() { if !buf.isEmpty { chunks.append(buf); buf = "" } }
        for s in sentences {
            if s.count > maxLen {
                flush()
                var line = ""
                for word in s.components(separatedBy: .whitespaces) where !word.isEmpty {
                    let cand = line.isEmpty ? word : line + " " + word
                    if cand.count <= maxLen { line = cand }
                    else { if !line.isEmpty { chunks.append(line) }; line = word }
                }
                if !line.isEmpty { chunks.append(line) }
            } else if (buf.count + 1 + s.count) <= maxLen {
                buf = buf.isEmpty ? s : buf + " " + s
            } else {
                flush(); buf = s
            }
        }
        flush()
        return chunks
    }

    // Tải audio 1 đoạn từ Google (TRẢ VỀ Data hoàn chỉnh) — phát bằng AVAudioPlayer nên KHÔNG
    // có khoảng lặng do streaming. Có User-Agent giống trình duyệt thật để Google không chặn.
    func fetchGoogle(_ text: String, completion: @escaping (Data?) -> Void) {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://translate.google.com/translate_tts?ie=UTF-8&tl=vi&client=tw-ob&q=\(encoded)") else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // Audio rỗng/bị chặn thường rất nhỏ → coi như thất bại.
            if let data, code == 200, data.count > 200 {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    // PREFETCH: tải sẵn audio của đoạn KẾ TIẾP trong lúc đoạn hiện tại đang đọc → hết khoảng lặng.
    func prefetchNextGoogle() {
        guard googleNextData == nil, let next = googleQueue.first else { return }
        fetchGoogle(next) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                // Chỉ giữ nếu đoạn này vẫn là đoạn đầu hàng đợi (chưa bị bỏ do live đông).
                if self.googleQueue.first == next { self.googleNextData = data }
            }
        }
    }

    func playNextGoogleItem() {
        guard !googleQueue.isEmpty else {
            isPlayingGoogle = false
            isSpeaking = false
            googleNextData = nil
            googlePrio.removeAll()
            pendingCount = elevenQueue.count
            updateNowPlaying(playing: false)
            return
        }

        isPlayingGoogle = true
        isSpeaking = true
        googleItemToken += 1
        let token = googleItemToken
        let text = googleQueue.removeFirst()
        if !googlePrio.isEmpty { googlePrio.removeFirst() }
        pendingCount = googleQueue.count + elevenQueue.count

        // Nếu đã prefetch sẵn đoạn này → phát NGAY (không đợi mạng = không có khoảng lặng).
        if let data = googleNextData {
            googleNextData = nil
            playGoogleData(data, token: token, retryText: text)
        } else {
            // Chưa kịp prefetch → tải đoạn này rồi phát.
            fetchGoogle(text) { [weak self] data in
                DispatchQueue.main.async {
                    guard let self, self.googleItemToken == token, self.isPlayingGoogle else { return }
                    if let data {
                        self.playGoogleData(data, token: token, retryText: nil)
                    } else {
                        // Google chặn/timeout đoạn này → bỏ qua, đọc tiếp ngay (không đứng im).
                        self.playNextGoogleItem()
                    }
                }
            }
        }
    }

    // Phát audio đã tải xong bằng AVAudioPlayer (mượt, chỉnh tốc độ giữ cao độ).
    func playGoogleData(_ data: Data, token: Int, retryText: String?) {
        do {
            activateSession()
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = googleSpeed
            player.volume = volume
            player.prepareToPlay()
            player.play()
            googleAudio = player
            updateNowPlaying(playing: true)
            // Ngay khi bắt đầu phát đoạn này → tải sẵn đoạn KẾ (prefetch) để liền mạch.
            prefetchNextGoogle()
        } catch {
            // Data hỏng → bỏ đoạn, đọc tiếp.
            if self.googleItemToken == token { playNextGoogleItem() }
        }
    }
}
