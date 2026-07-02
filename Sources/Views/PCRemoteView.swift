import SwiftUI

// ============================================================================
//  PC Remote Controller — điều khiển máy tính từ app
//  App gọi HTTP tới Agent chạy trên PC (mở ra ngoài bằng ngrok):
//   GET  /ping                → kiểm tra kết nối
//   GET  /screen              → ảnh JPEG màn hình PC (xem trực tiếp)
//   POST /move   {dx,dy}      → di chuyển con trỏ
//   POST /click  {button}     → left / right / double
//   POST /scroll {amount}     → cuộn
//   POST /type   {text}       → gõ chữ
//   POST /key    {name}       → phím đặc biệt (enter/backspace/space...)
//   POST /media  {action}     → playpause/next/prev/mute/volup/voldown
//   POST /system {action}     → desktop / lock
//  Bảo mật: mọi request kèm header X-User + X-Pass (khớp với Agent trên PC).
// ============================================================================

@MainActor
final class PCRemoteEngine: ObservableObject {
    @Published var ip: String = ""
    @Published var port: String = "8765"
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var connected = false
    @Published var connecting = false
    @Published var error: String?
    @Published var screen: UIImage?
    @Published var previewOn = true

    var speed: Double = 2.5

    private let kIP = "pc_ip", kPort = "pc_port", kUser = "pc_user", kPass = "pc_pass"
    private var moveDX = 0.0, moveDY = 0.0
    private var moveTimer: Timer?
    private var previewTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        ip = d.string(forKey: kIP) ?? ""
        port = d.string(forKey: kPort) ?? "8765"
        username = d.string(forKey: kUser) ?? ""
        password = Keychain.load(kPass) ?? ""
    }

    var hasSavedLogin: Bool {
        !ip.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    // Ghép base URL từ IP + cổng (chấp nhận cả khi dán sẵn http://... hoặc link ngrok)
    private var normalizedBase: String {
        var s = ip.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        if s.contains("://") {
            if s.hasSuffix("/") { s = String(s.dropLast()) }
            return s
        }
        let p = port.trimmingCharacters(in: .whitespaces)
        return "http://\(s):\(p.isEmpty ? "8765" : p)"
    }

    private func request(_ path: String, method: String = "POST", json: [String: Any]? = nil) -> URLRequest? {
        guard let url = URL(string: normalizedBase + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 8
        r.setValue(username, forHTTPHeaderField: "X-User")
        r.setValue(password, forHTTPHeaderField: "X-Pass")
        r.setValue("true", forHTTPHeaderField: "ngrok-skip-browser-warning")
        if let json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return r
    }

    // MARK: Kết nối

    func connect() async {
        guard !ip.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Nhập IP máy tính."; return
        }
        connecting = true; error = nil
        defer { connecting = false }
        guard let req = request("/ping", method: "GET") else { error = "Địa chỉ không hợp lệ."; return }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                connected = true
                let d = UserDefaults.standard
                d.set(ip, forKey: kIP); d.set(port, forKey: kPort); d.set(username, forKey: kUser)
                Keychain.save(kPass, password)
                startPreview()
            } else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                error = code == 401 ? "Sai tài khoản hoặc mật khẩu." : "PC không phản hồi (mã \(code)). Kiểm tra PC đã chạy Agent + cùng mạng Wi-Fi chưa."
                _ = data
            }
        } catch {
            self.error = "Không kết nối được — kiểm tra IP + cùng Wi-Fi với PC. (\(error.localizedDescription))"
        }
    }

    func disconnect() {
        stopPreview()
        connected = false
    }

    func forget() {
        disconnect()
        let d = UserDefaults.standard
        [kIP, kPort, kUser].forEach { d.removeObject(forKey: $0) }
        Keychain.delete(kPass)
        ip = ""; port = "8765"; username = ""; password = ""
    }

    // MARK: Xem màn hình (poll ảnh JPEG)

    func startPreview() {
        stopPreview()
        previewTask = Task { @MainActor in
            while !Task.isCancelled, connected {
                if previewOn, let req = request("/screen", method: "GET") {
                    if let (data, resp) = try? await URLSession.shared.data(for: req),
                       (resp as? HTTPURLResponse)?.statusCode == 200,
                       let img = UIImage(data: data) {
                        screen = img
                    }
                }
                try? await Task.sleep(nanoseconds: 700_000_000)   // ~1.4 khung/giây
            }
        }
    }

    func stopPreview() {
        previewTask?.cancel(); previewTask = nil
    }

    // MARK: Di chuyển con trỏ (gom delta, đẩy đều mỗi 60ms cho mượt)

    func queueMove(dx: Double, dy: Double) {
        moveDX += dx * speed
        moveDY += dy * speed
        if moveTimer == nil {
            moveTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.flushMove() }
            }
        }
    }

    private func flushMove() {
        let dx = Int(moveDX.rounded()), dy = Int(moveDY.rounded())
        moveDX = 0; moveDY = 0
        if dx == 0 && dy == 0 {
            moveTimer?.invalidate(); moveTimer = nil
            return
        }
        fire("/move", ["dx": dx, "dy": dy])
    }

    // MARK: Các lệnh khác

    func click(_ button: String) { fire("/click", ["button": button]) }
    func scroll(_ amount: Int)   { fire("/scroll", ["amount": amount]) }
    func type(_ text: String)    { guard !text.isEmpty else { return }; fire("/type", ["text": text]) }
    func key(_ name: String)     { fire("/key", ["name": name]) }
    func media(_ action: String) { fire("/media", ["action": action]) }
    func system(_ action: String){ fire("/system", ["action": action]) }

    private func fire(_ path: String, _ body: [String: Any]) {
        guard connected, let req = request(path, json: body) else { return }
        Task { _ = try? await URLSession.shared.data(for: req) }
    }
}

struct PCRemoteView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var pc = PCRemoteEngine()
    @State private var autoTried = false

    var body: some View {
        NavigationStack {
            Group {
                if pc.connected { controller }
                else { connectForm }
            }
            .navigationTitle("PC Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if pc.connected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Ngắt") { pc.disconnect() }.foregroundStyle(.red)
                    }
                }
            }
        }
        .onAppear {
            if !autoTried, !pc.connected, pc.hasSavedLogin {
                autoTried = true
                Task { await pc.connect() }
            }
        }
        .onDisappear { pc.stopPreview() }
    }

    // MARK: - Form kết nối

    private var connectForm: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 52)).foregroundStyle(Theme.accent)
                    Text("PC Remote Controller").font(.title2.bold())
                    Text("Điều khiển máy tính từ điện thoại")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 12) {
                    field("IP máy tính") {
                        TextField("vd: 192.168.1.10", text: $pc.ip)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.numbersAndPunctuation)
                    }
                    field("Cổng (Port)") {
                        TextField("8765", text: $pc.port).keyboardType(.numberPad)
                    }
                    field("Tài khoản") {
                        TextField("vd: admin", text: $pc.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    field("Mật khẩu") {
                        SecureField("Mật khẩu (trùng với Agent trên PC)", text: $pc.password)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                }

                if let e = pc.error {
                    Text(e).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await pc.connect() }
                } label: {
                    HStack {
                        if pc.connecting { ProgressView().tint(.white) }
                        Text(pc.connecting ? "Đang kết nối..." : "Kết nối PC").font(.headline)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(LinearGradient(colors: [Theme.accent, Theme.purple],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(pc.connecting)

                if pc.hasSavedLogin {
                    Button(role: .destructive) { pc.forget() } label: {
                        Text("Xoá kết nối đã lưu").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }.buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Cần làm trên PC trước:").font(.caption.bold())
                    Text("1. Chạy file Agent (pc_remote.py) trên máy tính.\n2. Mở ngrok: ngrok http 8765 → copy link https vào ô trên.\n3. Nhập đúng Token đã đặt trong Agent.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding().background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding()
        }
    }

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            content().padding(12).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Bộ điều khiển

    private var controller: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("PC CONTROLLER")
                    .font(.headline.bold()).foregroundStyle(Theme.accent)
                    .padding(.top, 4)

                screenPreview
                trackpad
                speedSlider
                clickButtons
                mediaGrid
                keyboardRow
            }
            .padding()
        }
    }

    private var screenPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(Color.black)
            if let img = pc.screen {
                Image(uiImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 6) {
                    ProgressView().tint(.white)
                    Text("Đang tải màn hình PC...").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        pc.previewOn.toggle()
                        if pc.previewOn { pc.startPreview() }
                    } label: {
                        Image(systemName: pc.previewOn ? "eye.fill" : "eye.slash.fill")
                            .padding(8).background(.ultraThinMaterial).clipShape(Circle())
                    }
                    .padding(8)
                }
                Spacer()
            }
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var trackpad: some View {
        HStack(spacing: 10) {
            // Vùng rê chuột
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground))
                Text("RÊ ĐỂ DI CHUỘT · CHẠM = CLICK TRÁI")
                    .font(.caption2.bold()).foregroundStyle(.secondary)
            }
            .frame(height: 240)
            .contentShape(Rectangle())
            .gesture(trackpadGesture)

            // Cột cuộn
            VStack(spacing: 0) {
                scrollButton(systemName: "chevron.up", amount: 3)
                Text("CUỘN").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary).rotationEffect(.degrees(0))
                scrollButton(systemName: "chevron.down", amount: -3)
            }
            .frame(width: 54, height: 240)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @State private var lastDrag: CGSize = .zero
    @State private var dragMoved: CGFloat = 0

    private var trackpadGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let dx = v.translation.width - lastDrag.width
                let dy = v.translation.height - lastDrag.height
                pc.queueMove(dx: Double(dx), dy: Double(dy))
                lastDrag = v.translation
                dragMoved += abs(dx) + abs(dy)
            }
            .onEnded { _ in
                if dragMoved < 8 { pc.click("left") }   // chạm nhẹ = click trái
                lastDrag = .zero; dragMoved = 0
            }
    }

    private func scrollButton(systemName: String, amount: Int) -> some View {
        Button { pc.scroll(amount) } label: {
            Image(systemName: systemName).font(.title3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var speedSlider: some View {
        HStack {
            Text("Tốc độ").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { pc.speed }, set: { pc.speed = $0 }), in: 0.5...5, step: 0.1)
            Text(String(format: "%.1fx", pc.speed))
                .font(.subheadline.bold()).foregroundStyle(Theme.accent)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var clickButtons: some View {
        HStack(spacing: 12) {
            bigButton("Click Trái", icon: "cursorarrow.click") { pc.click("left") }
            bigButton("Click Phải", icon: "cursorarrow.click.2") { pc.click("right") }
        }
    }

    private let padCols = [GridItem(.flexible()), GridItem(.flexible()),
                           GridItem(.flexible()), GridItem(.flexible())]

    private var mediaGrid: some View {
        LazyVGrid(columns: padCols, spacing: 10) {
            padButton("Prev", "backward.end.fill") { pc.media("prev") }
            padButton("Play/Pause", "playpause.fill") { pc.media("playpause") }
            padButton("Next", "forward.end.fill") { pc.media("next") }
            padButton("Mute", "speaker.slash.fill") { pc.media("mute") }
            padButton("Vol -", "speaker.wave.1.fill") { pc.media("voldown") }
            padButton("Vol +", "speaker.wave.3.fill") { pc.media("volup") }
            padButton("Desktop", "menubar.dock.rectangle") { pc.system("desktop") }
            padButton("Lock PC", "lock.fill") { pc.system("lock") }
        }
    }

    @State private var typed = ""
    @State private var lastTyped = ""
    @FocusState private var kbFocused: Bool

    private var keyboardRow: some View {
        VStack(spacing: 10) {
            // TextField ẩn để bật bàn phím iOS + gõ chữ gửi sang PC
            TextField("", text: $typed)
                .focused($kbFocused)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .opacity(0.02).frame(height: 1)
                .onChange(of: typed) { newVal in
                    // Gửi phần vừa gõ thêm
                    if newVal.count > lastTyped.count {
                        let added = String(newVal.dropFirst(lastTyped.count))
                        pc.type(added)
                    } else if newVal.count < lastTyped.count {
                        pc.key("backspace")
                    }
                    lastTyped = newVal
                    if newVal.count > 200 { typed = ""; lastTyped = "" }
                }

            LazyVGrid(columns: padCols, spacing: 10) {
                padButton("Bàn phím", "keyboard") { kbFocused = true }
                padButton("Xoá", "delete.left") { pc.key("backspace") }
                padButton("Cách", "space") { pc.key("space") }
                padButton("Enter", "return") { pc.key("enter") }
            }
        }
    }

    // MARK: - Nút bấm

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func padButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(Theme.accent)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: 64)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
