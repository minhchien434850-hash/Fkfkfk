import SwiftUI
import AVFoundation
import HaishinKit

// ============================================================
//  Phát trực tiếp BẰNG CAMERA ngay trong app KENIOS (RTMP → VPS → HLS).
//  Chủ phòng mở camera + mic, đẩy luồng tới rtmp://VPS:1935/live với
//  tên luồng = streamKey. Người xem coi qua link HLS như cũ.
// ============================================================

@MainActor
final class LivePublisher: NSObject, ObservableObject {
    let connection = RTMPConnection()
    private(set) lazy var stream = RTMPStream(connection: connection)

    @Published var isLive = false
    @Published var status = "Đang chuẩn bị..."
    @Published var micMuted = false

    private var rtmpURL = ""
    private var streamName = ""
    private var position: AVCaptureDevice.Position = .front
    private var attached = false

    /// Bật camera + mic, hiển thị xem trước (chưa phát).
    func prepare() {
        guard !attached else { return }
        attached = true
        // Phiên âm thanh cho phép vừa thu vừa phát
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .videoRecording,
            options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        stream.sessionPreset = .hd1280x720
        stream.videoOrientation = .portrait
        attachDevices()
        status = "Sẵn sàng phát"
    }

    private func attachDevices() {
        stream.attachAudio(AVCaptureDevice.default(for: .audio)) { _, error in
            if let error { print("attachAudio:", error) }
        }
        stream.attachCamera(
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            track: 0
        ) { _, error in
            if let error { print("attachCamera:", error) }
        }
    }

    /// Bắt đầu đẩy luồng tới máy chủ.
    func start(rtmp: String, key: String) {
        rtmpURL = rtmp
        streamName = key
        status = "Đang kết nối máy chủ..."
        connection.addEventListener(.rtmpStatus, selector: #selector(onStatus), observer: self)
        connection.addEventListener(.ioError, selector: #selector(onError), observer: self)
        connection.connect(rtmp)
    }

    @objc private func onStatus(_ notification: Notification) {
        let e = Event.from(notification)
        guard let data = e.data as? ASObject, let code = data["code"] as? String else { return }
        DispatchQueue.main.async {
            switch code {
            case RTMPConnection.Code.connectSuccess.rawValue:
                self.stream.publish(self.streamName)
                self.isLive = true
                self.status = "🔴 Đang phát trực tiếp"
            case RTMPConnection.Code.connectClosed.rawValue:
                self.isLive = false
                self.status = "Đã ngắt kết nối"
            case RTMPConnection.Code.connectFailed.rawValue:
                self.isLive = false
                self.status = "Không kết nối được máy chủ live. Kiểm tra VPS đã cài máy chủ RTMP chưa."
            default:
                break
            }
        }
    }

    @objc private func onError(_ notification: Notification) {
        DispatchQueue.main.async {
            self.status = "Lỗi đường truyền — đang thử lại..."
        }
    }

    func flipCamera() {
        position = (position == .front) ? .back : .front
        stream.attachCamera(
            AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
            track: 0
        ) { _, _ in }
    }

    func toggleMic() {
        micMuted.toggle()
        stream.audioMixerSettings.isMuted = micMuted
    }

    func stop() {
        stream.close()
        connection.removeEventListener(.rtmpStatus, selector: #selector(onStatus), observer: self)
        connection.removeEventListener(.ioError, selector: #selector(onError), observer: self)
        connection.close()
        stream.attachAudio(nil)
        stream.attachCamera(nil, track: 0)
        isLive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// Xem trước camera bằng MTHKView của HaishinKit
struct LivePreviewView: UIViewRepresentable {
    let stream: RTMPStream
    func makeUIView(context: Context) -> MTHKView {
        let v = MTHKView(frame: .zero)
        v.videoGravity = .resizeAspectFill
        v.attachStream(stream)
        return v
    }
    func updateUIView(_ uiView: MTHKView, context: Context) {}
}

// ======================== Màn hình chủ phòng phát camera ========================
struct HostCameraLiveView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let room: LiveRoom

    @StateObject private var pub = LivePublisher()
    @State private var comments: [LiveComment] = []
    @State private var lastId = 0
    @State private var input = ""
    @State private var likes = 0
    @State private var viewers = 0
    @State private var ended = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LivePreviewView(stream: pub.stream).ignoresSafeArea()

            VStack(spacing: 0) {
                // Thanh trên: trạng thái + đóng
                HStack {
                    HStack(spacing: 6) {
                        Circle().fill(pub.isLive ? Color.red : Color.gray).frame(width: 9, height: 9)
                        Text(pub.isLive ? "LIVE" : "CHƯA PHÁT").font(.caption2.bold())
                        Label("\(viewers)", systemImage: "eye.fill").font(.caption2)
                        Label("\(likes)", systemImage: "heart.fill").font(.caption2)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.black.opacity(0.45)).clipShape(Capsule())
                    .foregroundStyle(.white)
                    Spacer()
                    Button { Task { await endLive() } } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14).padding(.top, 54)

                Text(pub.status).font(.caption2).foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)

                Spacer()

                // Bình luận thời gian thực
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(comments) { c in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(c.username ?? "ẩn danh").font(.caption.bold()).foregroundStyle(Theme.gold)
                                    Text(c.content).font(.caption).foregroundStyle(.white)
                                }.id(c.id)
                            }
                        }.padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 150)
                    .onChange(of: comments.count) { _ in
                        if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }

                // Nút điều khiển chính
                HStack(spacing: 14) {
                    controlButton(pub.micMuted ? "mic.slash.fill" : "mic.fill") { pub.toggleMic() }
                    controlButton("arrow.triangle.2.circlepath.camera.fill") { pub.flipCamera() }
                    Spacer()
                    if pub.isLive {
                        Button { Task { await endLive() } } label: {
                            Text("Kết thúc").font(.subheadline.bold())
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(Color.red).foregroundStyle(.white).clipShape(Capsule())
                        }
                    } else {
                        Button { startLive() } label: {
                            Text("Bắt đầu phát").font(.subheadline.bold())
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(Color.red).foregroundStyle(.white).clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 8)

                // Nhập bình luận
                HStack(spacing: 8) {
                    TextField("Bình luận...", text: $input)
                        .padding(10).background(Color.white.opacity(0.15))
                        .foregroundStyle(.white).clipShape(Capsule())
                        .submitLabel(.send).onSubmit { Task { await send() } }
                    Button { Task { await send() } } label: {
                        Image(systemName: "paperplane.fill").foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 18)
            }
        }
        .onAppear {
            pub.prepare()
            likes = room.likes; viewers = room.viewers
        }
        .task { await pollComments() }
        .onDisappear { pub.stop() }
    }

    private func controlButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.4)).clipShape(Circle())
        }
    }

    private func startLive() {
        guard let rtmp = room.rtmpUrl, let key = room.streamKey, !rtmp.isEmpty, !key.isEmpty else {
            pub.status = "Thiếu thông tin máy chủ live."
            return
        }
        pub.start(rtmp: rtmp, key: key)
    }

    private func endLive() async {
        guard !ended else { return }
        ended = true
        pub.stop()
        _ = try? await store.api.liveEnd(room.id)
        dismiss()
    }

    private func send() async {
        let t = input.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        input = ""
        try? await store.api.liveComment(room.id, content: t)
    }

    private func pollComments() async {
        try? await store.api.liveJoin(room.id)
        while !Task.isCancelled {
            if let i = try? await store.api.liveInfo(room.id) {
                likes = i.likes; viewers = i.viewers
            }
            if let cs = try? await store.api.liveComments(room.id, after: lastId), !cs.isEmpty {
                comments.append(contentsOf: cs)
                lastId = cs.last?.id ?? lastId
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
        }
    }
}
