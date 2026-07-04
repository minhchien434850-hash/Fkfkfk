import SwiftUI
import AVFoundation
import CoreImage
import ImageIO
import UIKit

// ============================================================================
//  Gọi thoại / video giữa bạn bè — relay khung hình + âm thanh qua máy chủ.
//  Video có BỘ LỌC LÀM ĐẸP (mịn da, sáng, hồng) + nhiều HIỆU ỨNG, áp trực tiếp
//  lên khung hình gửi đi nên người kia thấy bản đã làm đẹp.
// ============================================================================

// MARK: - Hiệu ứng
enum CallEffect: String, CaseIterable, Identifiable {
    case original, mono, transfer, process, instant, chrome, fade, noir
    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: return "Gốc"
        case .mono:     return "Đen trắng"
        case .transfer: return "Cổ điển"
        case .process:  return "Điện ảnh"
        case .instant:  return "Ấm"
        case .chrome:   return "Rực rỡ"
        case .fade:     return "Nhạt"
        case .noir:     return "Tương phản"
        }
    }
    var ciName: String? {
        switch self {
        case .original: return nil
        case .mono:     return "CIPhotoEffectMono"
        case .transfer: return "CIPhotoEffectTransfer"
        case .process:  return "CIPhotoEffectProcess"
        case .instant:  return "CIPhotoEffectInstant"
        case .chrome:   return "CIPhotoEffectChrome"
        case .fade:     return "CIPhotoEffectFade"
        case .noir:     return "CIPhotoEffectNoir"
        }
    }
}

// MARK: - Máy xử lý ảnh (làm đẹp + hiệu ứng)
final class BeautyEngine {
    static let shared = BeautyEngine()
    let ctx = CIContext(options: [.useSoftwareRenderer: false])
    private let rgb = CGColorSpaceCreateDeviceRGB()

    /// Áp làm đẹp (mịn da + sáng + bão hoà) rồi tới hiệu ứng.
    func process(_ input: CIImage, beauty: Double, effect: CallEffect) -> CIImage {
        var img = input
        if beauty > 0.01 {
            let r = 1.5 + beauty * 6.0
            let blurred = img.clampedToExtent().applyingGaussianBlur(sigma: r).cropped(to: img.extent)
            let a = CGFloat(min(0.85, beauty * 0.8))
            let soft = blurred.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
            img = soft.composited(over: img)
            img = img.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.05 * beauty,
                kCIInputSaturationKey: 1.0 + 0.12 * beauty,
                kCIInputContrastKey: 1.0 + 0.03 * beauty])
            // hồng hào nhẹ (tăng kênh đỏ chút xíu)
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1.0 + 0.06 * beauty, y: 0, z: 0, w: 0)])
        }
        if let name = effect.ciName, let f = CIFilter(name: name) {
            f.setValue(img, forKey: kCIInputImageKey)
            if let out = f.outputImage { img = out }
        }
        return img
    }

    func cgImage(_ ci: CIImage) -> CGImage? { ctx.createCGImage(ci, from: ci.extent) }

    func jpeg(_ ci: CIImage, quality: CGFloat) -> Data? {
        let key = CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String)
        return ctx.jpegRepresentation(of: ci, colorSpace: rgb, options: [key: quality])
    }
}

// MARK: - Camera + làm đẹp thời gian thực
final class CameraCapture: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var localImage: UIImage?
    var beauty: Double = 0.5
    var effect: CallEffect = .original
    var enabled = true
    var onFrameJPEG: ((Data) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "kenios.call.camera")
    private var useFront = true
    private var lastUpload = Date.distantPast
    private let uploadInterval: TimeInterval = 0.12   // ~8 khung/giây gửi đi

    func start() { queue.async { self.configure(); if !self.session.isRunning { self.session.startRunning() } } }
    func stop()  { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func flip()  { useFront.toggle(); queue.async { self.setInput() } }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480
        setInput()
        if session.canAddOutput(output) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(output)
        }
        session.commitConfiguration()
        applyConnection()
    }

    private func setInput() {
        session.beginConfiguration()
        for i in session.inputs { session.removeInput(i) }
        let pos: AVCaptureDevice.Position = useFront ? .front : .back
        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: pos),
           let input = try? AVCaptureDeviceInput(device: dev), session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        applyConnection()
    }

    private func applyConnection() {
        guard let conn = output.connection(with: .video) else { return }
        if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        if conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = useFront
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard enabled, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let base = CIImage(cvPixelBuffer: pb)
        let ci = BeautyEngine.shared.process(base, beauty: beauty, effect: effect)
        if let cg = BeautyEngine.shared.cgImage(ci) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async { self.localImage = ui }
        }
        let now = Date()
        if now.timeIntervalSince(lastUpload) >= uploadInterval, let cb = onFrameJPEG {
            lastUpload = now
            let small = ci.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
            if let data = BeautyEngine.shared.jpeg(small, quality: 0.4) { cb(data) }
        }
    }
}

// MARK: - Âm thanh 2 chiều (thu + phát, 16kHz mono PCM)
final class CallAudio {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let fmt16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let fmtFloat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    var onChunk: ((Data) -> Void)?
    var muted = false

    func start(speaker: Bool) {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playAndRecord, mode: .voiceChat,
                           options: speaker ? [.allowBluetooth, .defaultToSpeaker] : [.allowBluetooth])
        try? s.setActive(true, options: [])
        try? s.overrideOutputAudioPort(speaker ? .speaker : .none)

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmtFloat)

        let input = engine.inputNode
        let inFmt = input.inputFormat(forBus: 0)
        guard inFmt.sampleRate > 0 else { return }
        converter = AVAudioConverter(from: inFmt, to: fmt16)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFmt) { [weak self] buf, _ in
            guard let self, !self.muted, let conv = self.converter else { return }
            let cap = AVAudioFrameCount(Double(buf.frameLength) * 16000.0 / inFmt.sampleRate) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: self.fmt16, frameCapacity: cap) else { return }
            var provided = false
            var err: NSError?
            let status = conv.convert(to: out, error: &err) { _, outStatus in
                if provided { outStatus.pointee = .noDataNow; return nil }
                provided = true; outStatus.pointee = .haveData; return buf
            }
            if status == .haveData, out.frameLength > 0, let ch = out.int16ChannelData {
                let data = Data(bytes: ch[0], count: Int(out.frameLength) * 2)
                self.onChunk?(data)
            }
        }
        engine.prepare()
        try? engine.start()
        player.play()
    }

    func setSpeaker(_ on: Bool) {
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(on ? .speaker : .none)
    }

    func play(int16 data: Data) {
        let count = data.count / 2
        guard count > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: fmtFloat, frameCapacity: AVAudioFrameCount(count)) else { return }
        buf.frameLength = AVAudioFrameCount(count)
        guard let out = buf.floatChannelData?[0] else { return }
        data.withUnsafeBytes { raw in
            let ints = raw.bindMemory(to: Int16.self)
            for i in 0..<count { out[i] = Float(ints[i]) / 32768.0 }
        }
        player.scheduleBuffer(buf, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Preview camera của mình (quan sát CameraCapture để cập nhật khung hình)
struct LocalPreview: View {
    @ObservedObject var camera: CameraCapture
    var body: some View {
        ZStack {
            Color.black
            if let me = camera.localImage {
                LiveImageView(image: me)
            }
        }
    }
}

// MARK: - Hiển thị UIImage nhanh (dùng cho preview + khung hình từ xa)
struct LiveImageView: UIViewRepresentable {
    var image: UIImage?
    var mode: UIView.ContentMode = .scaleAspectFill
    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView(); v.contentMode = mode; v.clipsToBounds = true
        v.backgroundColor = .black; return v
    }
    func updateUIView(_ v: UIImageView, context: Context) { v.image = image }
}

// MARK: - Phiên gọi (điều phối tín hiệu + media)
@MainActor
final class CallSession: ObservableObject {
    enum Phase { case ringing, active, ended }
    @Published var phase: Phase
    @Published var remoteImage: UIImage?
    @Published var muted = false
    @Published var speakerOn = true
    @Published var cameraOn: Bool
    @Published var beauty: Double = 0.5
    @Published var effect: CallEffect = .original
    @Published var durationText = "00:00"
    @Published var statusText = ""

    let callId: String
    let peerName: String
    let isVideo: Bool
    let isCaller: Bool
    let camera = CameraCapture()
    private let audio = CallAudio()
    private let api: APIClient
    private let onClose: () -> Void

    private var timers: [Timer] = []
    private var lastAudioSeq = 0
    private var startedAt: Date?
    private var ended = false

    init(callId: String, peerName: String, isVideo: Bool, isCaller: Bool,
         api: APIClient, onClose: @escaping () -> Void) {
        self.callId = callId; self.peerName = peerName
        self.isVideo = isVideo; self.isCaller = isCaller
        self.api = api; self.onClose = onClose
        self.cameraOn = isVideo
        self.phase = .ringing
        self.statusText = isCaller ? "Đang gọi..." : "Cuộc gọi đến"
    }

    // Người gọi bắt đầu chờ máy; người nhận đợi bấm "Nghe".
    func begin() {
        if isVideo { startCamera() }
        // Poll trạng thái để biết đối phương nghe/từ chối/kết thúc.
        addTimer(1.0) { [weak self] in Task { await self?.pollState() } }
        // Hết giờ đổ chuông (chỉ khi vẫn đang chờ máy)
        if isCaller {
            addTimer(45) { [weak self] in
                if self?.phase == .ringing { self?.hangUp(reason: "Không có phản hồi") }
            }
        }
    }

    // Người nhận bấm Nghe.
    func accept() {
        Task {
            try? await api.callAnswer(callId, accept: true)
            await MainActor.run { self.goActive() }
        }
    }
    func decline() {
        Task { try? await api.callAnswer(callId, accept: false); await MainActor.run { self.close() } }
    }

    private func pollState() async {
        guard !ended else { return }
        guard let st = try? await api.callState(callId) else { return }
        switch st.state {
        case "active": if phase == .ringing { goActive() }
        case "declined": statusText = "Đã từ chối"; endLocalAndClose()
        case "ended": endLocalAndClose()
        default: break
        }
    }

    private func goActive() {
        guard phase == .ringing else { return }
        phase = .active
        statusText = ""
        startedAt = Date()
        if isVideo { startCamera() }
        startAudio()
        // Gửi/nhận khung hình (capture giá trị cục bộ vì closure chạy trên luồng camera)
        let api = self.api
        let cid = self.callId
        if isVideo {
            camera.onFrameJPEG = { data in
                let b64 = data.base64EncodedString()
                Task { try? await api.callPutFrame(cid, jpgBase64: b64) }
            }
            addTimer(0.12) { [weak self] in Task { await self?.pullFrame() } }
        }
        // Âm thanh
        audio.onChunk = { data in
            let b64 = data.base64EncodedString()
            Task { try? await api.callPutAudio(cid, pcmBase64: b64) }
        }
        addTimer(0.2) { [weak self] in Task { await self?.pullAudio() } }
        // Đồng hồ
        addTimer(1.0) { [weak self] in self?.tick() }
    }

    private func startCamera() { camera.beauty = beauty; camera.effect = effect; camera.enabled = cameraOn; camera.start() }
    private func startAudio() { audio.muted = muted; audio.start(speaker: speakerOn) }

    private func pullFrame() async {
        guard phase == .active, let f = try? await api.callGetFrame(callId), !f.jpg.isEmpty,
              let data = Data(base64Encoded: f.jpg), let img = UIImage(data: data) else { return }
        remoteImage = img
    }
    private func pullAudio() async {
        guard phase == .active, let r = try? await api.callGetAudio(callId, after: lastAudioSeq) else { return }
        for ch in r.chunks {
            if ch.seq > lastAudioSeq { lastAudioSeq = ch.seq }
            if let d = Data(base64Encoded: ch.pcm) { audio.play(int16: d) }
        }
    }

    private func tick() {
        guard let s = startedAt else { return }
        let sec = Int(Date().timeIntervalSince(s))
        durationText = String(format: "%02d:%02d", sec / 60, sec % 60)
    }

    // MARK: điều khiển
    func toggleMute() { muted.toggle(); audio.muted = muted }
    func toggleSpeaker() { speakerOn.toggle(); audio.setSpeaker(speakerOn) }
    func toggleCamera() { cameraOn.toggle(); camera.enabled = cameraOn }
    func flipCamera() { camera.flip() }
    func setBeauty(_ v: Double) { beauty = v; camera.beauty = v }
    func setEffect(_ e: CallEffect) { effect = e; camera.effect = e }

    func hangUp(reason: String? = nil) {
        if let reason { statusText = reason }
        Task { try? await api.callEnd(callId) }
        endLocalAndClose()
    }

    private func endLocalAndClose() {
        guard !ended else { return }
        phase = .ended
        // để người dùng thấy trạng thái 1 nhịp rồi đóng
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.close() }
    }

    private func close() {
        guard !ended else { return }
        ended = true
        timers.forEach { $0.invalidate() }; timers.removeAll()
        camera.stop(); audio.stop()
        onClose()
    }

    private func addTimer(_ interval: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in block() }
        }
        timers.append(t)
    }

    deinit { timers.forEach { $0.invalidate() } }
}

// MARK: - Màn hình cuộc gọi
struct CallScreen: View {
    @StateObject private var session: CallSession
    let onClose: () -> Void

    init(call: ActiveCall, api: APIClient, onClose: @escaping () -> Void) {
        self.onClose = onClose
        _session = StateObject(wrappedValue: CallSession(
            callId: call.callId, peerName: call.peerName, isVideo: call.video,
            isCaller: !call.incoming, api: api, onClose: onClose))
    }

    var body: some View {
        ZStack {
            if session.isVideo && session.phase == .active {
                videoActive
            } else {
                audioOrRinging
            }
        }
        .onAppear { session.begin() }
        .statusBarHidden(true)
    }

    // Giao diện video khi đang gọi
    private var videoActive: some View {
        ZStack(alignment: .bottom) {
            // Khung hình người kia (nền lớn)
            if let img = session.remoteImage {
                LiveImageView(image: img).ignoresSafeArea()
            } else {
                LinearGradient(colors: [.black, Color(.darkGray)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Đang kết nối hình ảnh...").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }

            // Khung hình mình (nhỏ, góc trên phải)
            VStack {
                HStack {
                    Spacer()
                    ZStack {
                        if session.cameraOn {
                            LocalPreview(camera: session.camera)
                        } else {
                            Color.black
                            Image(systemName: "video.slash.fill").foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(width: 108, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.3)))
                    .padding(.top, 60).padding(.trailing, 16)
                }
                Spacer()
            }

            // Tên + thời lượng
            VStack {
                Text(session.peerName).font(.headline).foregroundStyle(.white)
                Text(session.durationText).font(.caption).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.top, 60).frame(maxHeight: .infinity, alignment: .top)

            // Bảng làm đẹp + hiệu ứng + nút điều khiển
            VStack(spacing: 14) {
                beautyPanel
                controlBar
            }
            .padding(.bottom, 30)
        }
        .background(Color.black.ignoresSafeArea())
    }

    // Giao diện gọi thoại hoặc đang đổ chuông
    private var audioOrRinging: some View {
        ZStack {
            LinearGradient(colors: [Theme.accent.opacity(0.9), .purple.opacity(0.8), .black],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.15)).frame(width: 130, height: 130)
                    Text(String(session.peerName.prefix(1)).uppercased())
                        .font(.system(size: 54, weight: .bold)).foregroundStyle(.white)
                }
                Text(session.peerName).font(.title.bold()).foregroundStyle(.white)
                Text(session.phase == .active ? session.durationText
                     : (session.statusText.isEmpty ? (session.isVideo ? "Cuộc gọi video" : "Cuộc gọi thoại") : session.statusText))
                    .font(.headline).foregroundStyle(.white.opacity(0.9))
                Spacer()

                if session.phase == .ringing && !session.isCaller {
                    // Người nhận: từ chối / nghe
                    HStack(spacing: 70) {
                        callButton("phone.down.fill", .red, "Từ chối") { session.decline() }
                        callButton(session.isVideo ? "video.fill" : "phone.fill", .green, "Nghe") { session.accept() }
                    }.padding(.bottom, 50)
                } else {
                    // Người gọi đang chờ, hoặc gọi thoại đang diễn ra
                    controlBar.padding(.bottom, 40)
                }
            }
        }
    }

    // Bảng làm đẹp + chọn hiệu ứng (chỉ khi video)
    private var beautyPanel: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars").foregroundStyle(.white)
                Text("Làm đẹp").font(.caption).foregroundStyle(.white)
                Slider(value: Binding(get: { session.beauty }, set: { session.setBeauty($0) }), in: 0...1)
                    .tint(.pink)
                Text("\(Int(session.beauty * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.white).frame(width: 38)
            }
            .padding(.horizontal, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CallEffect.allCases) { e in
                        Button { session.setEffect(e) } label: {
                            Text(e.label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(session.effect == e ? Color.pink : Color.white.opacity(0.18))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
    }

    // Hàng nút điều khiển
    private var controlBar: some View {
        HStack(spacing: 22) {
            ctrl(session.muted ? "mic.slash.fill" : "mic.fill", session.muted ? .red : .white) { session.toggleMute() }
            if session.isVideo {
                ctrl(session.cameraOn ? "video.fill" : "video.slash.fill", .white) { session.toggleCamera() }
                ctrl("arrow.triangle.2.circlepath.camera.fill", .white) { session.flipCamera() }
            }
            ctrl(session.speakerOn ? "speaker.wave.2.fill" : "speaker.fill", .white) { session.toggleSpeaker() }
            ctrl("phone.down.fill", .white, bg: .red) { session.hangUp() }
        }
    }

    private func ctrl(_ icon: String, _ tint: Color, bg: Color = .white.opacity(0.18),
                      _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint)
                .frame(width: 56, height: 56).background(bg).clipShape(Circle())
        }
    }

    private func callButton(_ icon: String, _ bg: Color, _ label: String,
                            _ action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon).font(.title).foregroundStyle(.white)
                    .frame(width: 72, height: 72).background(bg).clipShape(Circle())
            }
            Text(label).font(.caption).foregroundStyle(.white)
        }
    }
}

// MARK: - Cuộc gọi hiện hành + điều phối tín hiệu đến (gắn ở gốc app)
struct ActiveCall: Identifiable, Equatable {
    let id = UUID()
    let callId: String
    let peerId: Int
    let peerName: String
    let video: Bool
    let incoming: Bool
}

@MainActor
final class CallCoordinator: ObservableObject {
    @Published var active: ActiveCall?
    private var pollTimer: Timer?
    private var api: APIClient?

    func configure(api: APIClient) { self.api = api }

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { await self?.checkIncoming() }
        }
    }
    func stopPolling() { pollTimer?.invalidate(); pollTimer = nil }

    private func checkIncoming() async {
        guard active == nil, let api else { return }
        if let inc = try? await api.callIncoming(), let cid = inc.callId {
            active = ActiveCall(callId: cid, peerId: inc.from ?? 0,
                                peerName: inc.fromName ?? "Bạn", video: inc.video ?? true, incoming: true)
        }
    }

    /// Gọi đi cho bạn bè.
    func placeCall(to friend: FriendItem, video: Bool) {
        guard let api else { return }
        Task {
            if let r = try? await api.callStart(to: friend.id, video: video) {
                await MainActor.run {
                    self.active = ActiveCall(callId: r.callId, peerId: friend.id,
                                             peerName: friend.username, video: video, incoming: false)
                }
            }
        }
    }

    func close() { active = nil }
}
