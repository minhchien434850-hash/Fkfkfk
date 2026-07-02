import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

struct DirectMessageChatView: View {
    let friend: FriendItem
    @EnvironmentObject var store: AppStore
    @State private var messageText = ""
    @State private var timer: Timer? = nil
    @State private var isSending = false
    @State private var sendError: String? = nil

    // Đa phương tiện
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var showFilePicker = false
    @State private var uploading = false
    @StateObject private var recorder = ChatVoiceRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // Chat history list
            ScrollViewReader { proxy in
                ScrollView {
                    let messages = store.directMessages[friend.id] ?? []
                    VStack(spacing: 12) {
                        if messages.isEmpty {
                            Text("Chưa có tin nhắn nào. Hãy gửi lời chào!")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(messages) { msg in
                                let isMe = msg.senderId != friend.id
                                HStack {
                                    if isMe { Spacer() }

                                    VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                                        bubble(for: msg, isMe: isMe)

                                        Text(formatTime(msg.createdAt))
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                    }

                                    if !isMe { Spacer() }
                                }
                                .id(msg.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: store.directMessages[friend.id]?.count) { _ in
                    if let last = store.directMessages[friend.id]?.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = store.directMessages[friend.id]?.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            if let err = sendError {
                Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }

            if uploading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Đang tải tệp lên...").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }

            inputBar
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startPolling() }
        .onDisappear { stopPolling(); recorder.cancel() }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPicker(contentTypes: [.item], allowsMultipleSelection: false, asCopy: true) { urls in
                if let u = urls.first { Task { await handlePickedFile(u) } }
            }.ignoresSafeArea()
        }
    }

    // MARK: - Bong bóng tin nhắn (văn bản / ảnh / video / âm thanh / tệp)
    @ViewBuilder
    private func bubble(for msg: DirectMessageItem, isMe: Bool) -> some View {
        if let media = ChatMedia.parse(msg.content) {
            VStack(alignment: isMe ? .trailing : .leading, spacing: 6) {
                switch media.kind {
                case "img":
                    AsyncImage(url: URL(string: media.url)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        ZStack { Color(.tertiarySystemFill); ProgressView() }
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                case "video":
                    Link(destination: URL(string: media.url) ?? URL(string: "https://")!) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85))
                                .frame(width: 200, height: 130)
                            Image(systemName: "play.circle.fill").font(.system(size: 44)).foregroundStyle(.white)
                            VStack { Spacer(); Text("Video").font(.caption2).foregroundStyle(.white.opacity(0.9)).padding(6) }
                                .frame(width: 200, height: 130, alignment: .bottomLeading)
                        }
                    }
                case "audio":
                    ChatAudioBubble(url: media.url, isMe: isMe)
                default: // tệp
                    Link(destination: URL(string: media.url) ?? URL(string: "https://")!) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill").font(.title3)
                            Text(media.caption.isEmpty ? "Tệp đính kèm" : media.caption)
                                .font(.caption).lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(isMe ? Theme.accent.opacity(0.85) : Color(.secondarySystemBackground))
                        .foregroundStyle(isMe ? .white : .primary)
                        .cornerRadius(14)
                    }
                }
                if !media.caption.isEmpty && media.kind != "file" {
                    Text(media.caption)
                        .font(.caption)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(isMe ? Theme.accent : Color(.secondarySystemBackground))
                        .foregroundStyle(isMe ? .white : .primary)
                        .cornerRadius(14)
                }
            }
        } else {
            Text(msg.content)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(isMe ? Theme.accent : Color(.secondarySystemBackground))
                .foregroundStyle(isMe ? .white : .primary)
                .cornerRadius(18)
        }
    }

    // MARK: - Thanh nhập liệu
    private var inputBar: some View {
        VStack(spacing: 6) {
            if recorder.isRecording {
                HStack(spacing: 10) {
                    Circle().fill(.red).frame(width: 10, height: 10)
                        .opacity(0.4 + 0.6 * (recorder.level))
                    Text("Đang ghi âm \(recorder.durationText)").font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Huỷ") { recorder.cancel() }.font(.caption).foregroundStyle(.secondary)
                    Button {
                        Task { await stopAndSendVoice() }
                    } label: {
                        Image(systemName: "paperplane.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal)
            }

            HStack(spacing: 10) {
                // Menu đính kèm
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .any(of: [.images, .videos])) {
                        Label("Ảnh / Video", systemImage: "photo.on.rectangle")
                    }
                    Button { showFilePicker = true } label: {
                        Label("Tệp", systemImage: "doc")
                    }
                    Button { recorder.start() } label: {
                        Label("Ghi âm giọng nói", systemImage: "mic")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2).foregroundStyle(Theme.accent)
                }
                .disabled(uploading || recorder.isRecording)

                TextField("Nhập tin nhắn...", text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(20)

                Button {
                    Task { await sendMessage() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.headline).foregroundStyle(.white).padding(10)
                            .background(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Theme.accent)
                            .clipShape(Circle())
                    }
                }
                .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
            }
            .padding()
        }
        .background(.thinMaterial)
    }

    // MARK: - Gửi văn bản
    private func sendMessage() async {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        isSending = true; sendError = nil
        do {
            _ = try await store.api.sendDirectMessage(receiverId: friend.id, content: content)
            messageText = ""
            await store.refreshDirectMessages(friendId: friend.id)
        } catch { sendError = error.localizedDescription }
        isSending = false
    }

    // MARK: - Gửi đa phương tiện
    private func sendMediaMessage(kind: String, url: String, caption: String) async {
        do {
            let payload = ChatMedia.encode(kind: kind, url: url, caption: caption)
            _ = try await store.api.sendDirectMessage(receiverId: friend.id, content: payload)
            await store.refreshDirectMessages(friendId: friend.id)
        } catch { sendError = error.localizedDescription }
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        uploading = true; sendError = nil
        defer { uploading = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                sendError = "Không đọc được tệp đã chọn."; return
            }
            let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
            let maxBytes = isVideo ? 700 * 1024 * 1024 : 30 * 1024 * 1024
            if data.count > maxBytes {
                sendError = "Tệp quá lớn (\(data.count / (1024*1024))MB)."; return
            }
            let mime = isVideo ? "video/mp4" : "image/jpeg"
            let name = "\(isVideo ? "video" : "img")_\(Int(Date().timeIntervalSince1970))"
            let link = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(), mime: mime, name: name)
            await sendMediaMessage(kind: isVideo ? "video" : "img", url: link, caption: "")
        } catch { sendError = error.localizedDescription }
    }

    private func handlePickedFile(_ srcURL: URL) async {
        uploading = true; sendError = nil
        defer { uploading = false }
        let access = srcURL.startAccessingSecurityScopedResource()
        defer { if access { srcURL.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: srcURL)
            if data.count > 700 * 1024 * 1024 { sendError = "Tệp quá lớn (>700MB)."; return }
            let name = srcURL.lastPathComponent
            let link = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(),
                                                       mime: "application/octet-stream", name: name)
            await sendMediaMessage(kind: "file", url: link, caption: name)
        } catch { sendError = error.localizedDescription }
    }

    private func stopAndSendVoice() async {
        uploading = true; sendError = nil
        defer { uploading = false }
        guard let url = recorder.stop() else { sendError = "Không ghi được âm thanh."; return }
        do {
            let data = try Data(contentsOf: url)
            let link = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(),
                                                       mime: "audio/mp4", name: "voice_\(Int(Date().timeIntervalSince1970)).m4a")
            await sendMediaMessage(kind: "audio", url: link, caption: "")
        } catch { sendError = error.localizedDescription }
    }

    // MARK: - Helpers
    private func startPolling() {
        Task { await store.refreshDirectMessages(friendId: friend.id) }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { await store.refreshDirectMessages(friendId: friend.id) }
        }
    }
    private func stopPolling() { timer?.invalidate(); timer = nil }

    private func formatTime(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Mã hoá/giải mã tin nhắn media (không cần đổi backend, dùng chuỗi content sẵn có)
enum ChatMedia {
    static let marker = "\u{2063}KMEDIA\u{2063}"   // ký tự vô hình, tránh trùng nội dung người dùng
    static func encode(kind: String, url: String, caption: String) -> String {
        "\(marker)\(kind)\(marker)\(url)\(marker)\(caption)"
    }
    static func parse(_ content: String) -> (kind: String, url: String, caption: String)? {
        guard content.hasPrefix(marker) else { return nil }
        let parts = content.components(separatedBy: marker)
        // parts[0] rỗng, [1]=kind, [2]=url, [3...]=caption
        guard parts.count >= 3, !parts[2].isEmpty else { return nil }
        let caption = parts.count >= 4 ? parts[3...].joined(separator: marker) : ""
        return (parts[1], parts[2], caption)
    }
}

// MARK: - Ghi âm giọng nói cho chat
final class ChatVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var level: Double = 0
    @Published var durationText = "0:00"
    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var startedAt: Date?
    private(set) var fileURL: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted, let self else { return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatvoice_\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.isMeteringEnabled = true
            r.record()
            recorder = r; fileURL = url; startedAt = Date(); isRecording = true
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.updateMeter()
            }
        } catch { isRecording = false }
    }

    private func updateMeter() {
        guard let r = recorder else { return }
        r.updateMeters()
        let power = r.averagePower(forChannel: 0)          // -160...0 dB
        level = max(0, min(1, Double((power + 50) / 50)))
        if let s = startedAt {
            let sec = Int(Date().timeIntervalSince(s))
            durationText = String(format: "%d:%02d", sec / 60, sec % 60)
        }
    }

    /// Dừng và trả về file ghi âm.
    func stop() -> URL? {
        meterTimer?.invalidate(); meterTimer = nil
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return fileURL
    }

    func cancel() {
        meterTimer?.invalidate(); meterTimer = nil
        recorder?.stop()
        if let u = fileURL { try? FileManager.default.removeItem(at: u) }
        fileURL = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Bong bóng phát âm thanh trong chat
struct ChatAudioBubble: View {
    let url: String
    let isMe: Bool
    @StateObject private var player = ChatAudioPlayer()

    var body: some View {
        Button {
            player.toggle(urlString: url)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                Image(systemName: "waveform")
                    .font(.title3)
                Text("Tin nhắn thoại").font(.caption)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isMe ? Theme.accent : Color(.secondarySystemBackground))
            .foregroundStyle(isMe ? .white : .primary)
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

final class ChatAudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(urlString: String) {
        if isPlaying { player?.stop(); isPlaying = false; return }
        guard let url = URL(string: urlString) else { return }
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                p.play()
                self.player = p
                self.isPlaying = true
            } catch { self.isPlaying = false }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
