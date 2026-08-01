import SwiftUI

// ============================================================================
//  Live Now System Engine — điều khiển Livestream/Restream FFmpeg trên VPS
//  Kết nối QUA máy chủ Kenios (dùng chung endpoint /ssh/exec đã có). App gửi
//  Host/Username/Password + lệnh → backend SSH tới VPS, chạy FFmpeg đẩy luồng
//  RTMP và truyền log về theo thời gian thực. Giao diện điều khiển tiếng Anh.
// ============================================================================

// MARK: - Models

enum LiveConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

enum LiveStreamStatus: Equatable {
    case offline
    case streaming
    case buffering
    case error(String)

    var label: String {
        switch self {
        case .offline:   return "OFFLINE"
        case .streaming: return "STREAMING"
        case .buffering: return "BUFFERING"
        case .error:     return "ERROR"
        }
    }
    var color: Color {
        switch self {
        case .offline:   return .gray
        case .streaming: return .red
        case .buffering: return .orange
        case .error:     return .yellow
        }
    }
}

struct LiveScriptPreset: Identifiable {
    let id = UUID()
    let title: String
    let bashCommand: String
}

let kLiveScriptPresets: [LiveScriptPreset] = [
    LiveScriptPreset(title: "Install FFmpeg",
                     bashCommand: "apt-get update -y && apt-get install -y ffmpeg && ffmpeg -version | head -n 1"),
    LiveScriptPreset(title: "Update Kenios backend",
                     bashCommand: "bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/capnhat-vps.sh)"),
    LiveScriptPreset(title: "Check FFmpeg processes",
                     bashCommand: "pgrep -af ffmpeg || echo 'No FFmpeg process running.'"),
    LiveScriptPreset(title: "Stop all FFmpeg",
                     bashCommand: "pkill -f ffmpeg && echo 'Stopped.' || echo 'Nothing to stop.'")
]

// MARK: - Engine (reuses Kenios SSH proxy: /ssh/exec)

@MainActor
final class LiveNowEngine: ObservableObject {
    // Server login
    @Published var host = ""
    @Published var port = "22"
    @Published var username = "root"
    @Published var password = ""

    @Published var connection: LiveConnectionState = .idle
    @Published var connectError: String?

    // Stream config
    @Published var sourceInput = "/root/live_source.mp4"
    @Published var streamUrl = "rtmp://a.rtmp.youtube.com/live2"
    @Published var streamKey = ""
    @Published var streamStatus: LiveStreamStatus = .offline

    // Runtime metrics — đọc THẬT từ dòng progress của FFmpeg (bitrate= / fps= / speed=)
    @Published var startedAt: Date?
    @Published var bitrateKbps: Int?
    @Published var fps: Int?
    @Published var speed: String?

    // Console
    @Published var consoleLogs = ""
    @Published var isBusy = false

    private let baseURL: String
    private let token: String
    private var monitorTask: Task<Void, Never>?
    private let logPath = "/root/kenios_live.log"

    // Khoá lưu đăng nhập (host/port/user ở UserDefaults, mật khẩu ở Keychain)
    private let kHost = "live_host", kPort = "live_port", kUser = "live_user", kPass = "live_password"

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
        let d = UserDefaults.standard
        if let h = d.string(forKey: kHost), !h.isEmpty { host = h }
        if let p = d.string(forKey: kPort), !p.isEmpty { port = p }
        if let u = d.string(forKey: kUser), !u.isEmpty { username = u }
        if let pw = Keychain.load(kPass), !pw.isEmpty { password = pw }
    }

    var hasSavedLogin: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    private func persistLogin() {
        let d = UserDefaults.standard
        d.set(host, forKey: kHost)
        d.set(port, forKey: kPort)
        d.set(username, forKey: kUser)
        Keychain.save(kPass, password)
    }

    func forgetLogin() {
        let d = UserDefaults.standard
        [kHost, kPort, kUser].forEach { d.removeObject(forKey: $0) }
        Keychain.delete(kPass)
        host = ""; port = "22"; username = "root"; password = ""
        connection = .idle; connectError = nil
    }

    private func request() -> URLRequest? {
        guard let url = URL(string: baseURL + "/ssh/exec") else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 3600
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func body(_ command: String) -> Data? {
        let dict: [String: Any] = [
            "host": host.trimmingCharacters(in: .whitespaces),
            "port": Int(port) ?? 22,
            "username": username.trimmingCharacters(in: .whitespaces),
            "password": password,
            "command": command
        ]
        return try? JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: Connect

    func connect() async {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            connectError = "Please fill Host and Username."
            return
        }
        connection = .connecting
        connectError = nil
        do {
            let out = try await runCollect("echo LIVE_ENGINE_OK")
            if out.contains("LIVE_ENGINE_OK") {
                connection = .connected
                persistLogin()   // lưu để lần sau tự kết nối
                consoleLogs = "Engine connected to \(host).\n"
                await refreshStatus()
            } else {
                connection = .failed("Unexpected response.")
                connectError = out.isEmpty ? "No response from server." : out
            }
        } catch {
            connection = .failed(error.localizedDescription)
            connectError = error.localizedDescription
        }
    }

    func disconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        connection = .idle
        streamStatus = .offline
        consoleLogs = ""
        connectError = nil
        startedAt = nil
        bitrateKbps = nil
        fps = nil
        speed = nil
        // Giữ lại đăng nhập để lần sau tự kết nối
    }

    // MARK: Live control

    /// Bật luồng: chạy FFmpeg nền, đẩy nguồn (loop) lên RTMP target.
    func startLiveStream() async {
        let url = streamUrl.trimmingCharacters(in: .whitespaces)
        let key = streamKey.trimmingCharacters(in: .whitespaces)
        let src = sourceInput.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !key.isEmpty, !src.isEmpty else {
            consoleLogs += "Execution Error: Source, Stream URL and Stream Key are required.\n"
            return
        }
        let target = url.hasSuffix("/") ? url + key : url + "/" + key
        // Dừng tiến trình cũ, chạy FFmpeg nền, ghi log ra file để theo dõi realtime.
        let cmd = """
        pkill -f 'ffmpeg' 2>/dev/null; sleep 1; \
        nohup ffmpeg -re -stream_loop -1 -i '\(src)' \
        -c:v libx264 -preset veryfast -b:v 2500k -maxrate 2500k -bufsize 5000k \
        -pix_fmt yuv420p -g 50 -c:a aac -b:a 128k -ar 44100 -f flv '\(target)' \
        > \(logPath) 2>&1 & echo "FFmpeg started (PID $!)"
        """
        streamStatus = .buffering
        await runStreaming(cmd)
        await refreshStatus()
        if streamStatus == .streaming {
            startedAt = Date()
            // Bật theo dõi log ngay để Runtime Metrics (bitrate/fps/speed) cập nhật realtime
            startMonitor()
        }
    }

    func stopLiveStream() async {
        stopMonitor()
        await runStreaming("pkill -f ffmpeg && echo 'Live stream stopped.' || echo 'No active stream.'")
        streamStatus = .offline
        startedAt = nil
        bitrateKbps = nil
        fps = nil
        speed = nil
    }

    /// Kiểm tra FFmpeg có đang chạy không để cập nhật trạng thái.
    func refreshStatus() async {
        do {
            let out = try await runCollect("pgrep -f 'ffmpeg' >/dev/null && echo RUNNING || echo STOPPED")
            if out.contains("RUNNING") { streamStatus = .streaming }
            else if out.contains("STOPPED") { streamStatus = .offline }
        } catch {
            streamStatus = .error(error.localizedDescription)
        }
    }

    // MARK: Console monitor (tail -f real-time)

    func startMonitor() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.runStreaming("tail -n 60 -f \(self.logPath) 2>/dev/null || echo 'No log yet. Start a stream first.'",
                                    checkCancel: true)
        }
    }

    func stopMonitor() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: Script automation

    func runOneLinerScript(_ command: String) async {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        guard connection == .connected else {
            consoleLogs += "Execution Error: Engine not connected.\n"
            return
        }
        await runStreaming(cmd)
    }

    // MARK: Low-level SSH calls (via backend /ssh/exec)

    private func runStreaming(_ command: String, checkCancel: Bool = false) async {
        guard var req = request() else {
            consoleLogs += "Execution Error: Invalid server URL.\n"
            return
        }
        req.httpBody = body(command)
        // Monitor (tail -f) chạy vô hạn — KHÔNG giữ cờ isBusy để không khoá nút Start/Stop
        if !checkCancel { isBusy = true }
        consoleLogs += "\n$ \(command.prefix(120))\n"
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                var msg = ""
                for try await line in bytes.lines { msg += line + "\n" }
                consoleLogs += "Execution Error: \(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)\n"
                if !checkCancel { isBusy = false }
                return
            }
            for try await line in bytes.lines {
                if checkCancel && Task.isCancelled { break }
                consoleLogs += line + "\n"
                parseMetrics(from: line)
                if consoleLogs.count > 60000 {
                    consoleLogs = String(consoleLogs.suffix(40000))
                }
            }
        } catch is CancellationError {
            consoleLogs += "\n[monitor stopped]\n"
        } catch {
            consoleLogs += "Execution Error: \(error.localizedDescription)\n"
        }
        if !checkCancel { isBusy = false }
    }

    /// Đọc số liệu từ dòng progress FFmpeg:
    /// "frame=  123 fps= 30 q=28.0 size= 1024kB time=00:00:04.10 bitrate=2045.6kbits/s speed=1.02x"
    private func parseMetrics(from line: String) {
        guard line.contains("bitrate=") || line.contains("speed=") else { return }
        if let r = line.range(of: #"bitrate=\s*([\d.]+)"#, options: .regularExpression) {
            let v = line[r].replacingOccurrences(of: "bitrate=", with: "").trimmingCharacters(in: .whitespaces)
            if let d = Double(v) { bitrateKbps = Int(d) }
        }
        if let r = line.range(of: #"fps=\s*([\d.]+)"#, options: .regularExpression) {
            let v = line[r].replacingOccurrences(of: "fps=", with: "").trimmingCharacters(in: .whitespaces)
            if let d = Double(v) { fps = Int(d) }
        }
        if let r = line.range(of: #"speed=\s*([\d.]+x)"#, options: .regularExpression) {
            speed = line[r].replacingOccurrences(of: "speed=", with: "").trimmingCharacters(in: .whitespaces)
        }
        if line.contains("bitrate="), streamStatus != .streaming {
            streamStatus = .streaming
            if startedAt == nil { startedAt = Date() }
        }
    }

    private func runCollect(_ command: String) async throws -> String {
        guard var req = request() else { throw URLError(.badURL) }
        req.httpBody = body(command)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "live", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : text])
        }
        return text
    }
}

// MARK: - Root

struct LiveNowRootView: View {
    @StateObject private var engine: LiveNowEngine
    @State private var autoTried = false

    init(baseURL: String, token: String) {
        _engine = StateObject(wrappedValue: LiveNowEngine(baseURL: baseURL, token: token))
    }

    var body: some View {
        NavigationStack {
            Group {
                if engine.connection == .connected {
                    LiveWorkspaceContainerView(engine: engine)
                } else {
                    LiveQuickConnectView(engine: engine)
                }
            }
        }
        .onAppear {
            if !autoTried, engine.connection == .idle, engine.hasSavedLogin {
                autoTried = true
                Task { await engine.connect() }
            }
        }
    }
}

// MARK: - Quick Connect (English form)

struct LiveQuickConnectView: View {
    @ObservedObject var engine: LiveNowEngine

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 8) {
                    Image(systemName: "video.circle.fill")
                        .font(.system(size: 60)).foregroundStyle(.red)
                    Text("Live Now System Engine").font(.title2.bold())
                    Text("Remote FFmpeg / RTMP control over your VPS")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 14) {
                    liveField("Host or IP Address") {
                        TextField("e.g. 192.168.1.1", text: $engine.host)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    liveField("Port") {
                        TextField("22", text: $engine.port).keyboardType(.numberPad)
                    }
                    liveField("Username") {
                        TextField("e.g. root", text: $engine.username)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    liveField("Password") {
                        SecureField("Required", text: $engine.password)
                    }
                }

                if let err = engine.connectError {
                    Text(err).font(.caption).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await engine.connect() }
                } label: {
                    HStack(spacing: 8) {
                        if engine.connection == .connecting { ProgressView().tint(.white) }
                        Image(systemName: "bolt.fill")
                        Text(engine.connection == .connecting ? "Connecting..." : "Connect Engine")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0),
                                                        Color(red: 0.85, green: 0.1, blue: 0.2)],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(engine.connection == .connecting)

                if engine.hasSavedLogin {
                    Button(role: .destructive) { engine.forgetLogin() } label: {
                        Text("Xoá đăng nhập đã lưu")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Đăng nhập được lưu an toàn trong Keychain — lần sau mở là tự kết nối. Chỉ mất khi xoá app hoặc bấm 'Xoá đăng nhập đã lưu'.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Live Now v2")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func liveField<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption.bold()).foregroundStyle(.secondary)
            content()
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Workspace (3 Tabs)

struct LiveWorkspaceContainerView: View {
    @ObservedObject var engine: LiveNowEngine

    var body: some View {
        TabView {
            LiveDashboardView(engine: engine)
                .tabItem { Label("Dashboard", systemImage: "slider.horizontal.3") }
            LiveConsoleView(engine: engine)
                .tabItem { Label("Console", systemImage: "terminal") }
            LiveScriptAutomationView(engine: engine)
                .tabItem { Label("Automation", systemImage: "bolt.fill") }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Disconnect") { engine.disconnect() }.foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Tab 1: Dashboard

struct LiveDashboardView: View {
    @ObservedObject var engine: LiveNowEngine

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                statusCard
                streamFormCard
                metricsCard
                actionButtons

                Text("FFmpeg loops the source and pushes it to the RTMP target. Requires FFmpeg installed on the VPS (use the Automation tab → Install FFmpeg).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Engine: \(engine.host)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Status").font(.headline)
                Spacer()
                Button { Task { await engine.refreshStatus() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            HStack(spacing: 10) {
                Circle().fill(engine.streamStatus.color).frame(width: 12, height: 12)
                Text(engine.streamStatus.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(engine.streamStatus.color)
            }
            if case let .error(msg) = engine.streamStatus {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var streamFormCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stream Configuration").font(.headline)

            liveInput("Source File or URL") {
                TextField("/root/live_source.mp4 or https://...", text: $engine.sourceInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            liveInput("Target Stream URL") {
                TextField("rtmp://a.rtmp.youtube.com/live2", text: $engine.streamUrl)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            liveInput("Stream Key") {
                SecureField("x-xxxx-xxxx-xxxx-xxxx", text: $engine.streamKey)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime Metrics").font(.headline)
            HStack {
                metricChip("Bitrate", engine.bitrateKbps.map { "\($0) kbps" } ?? "--")
                metricChip("FPS", engine.fps.map(String.init) ?? "--")
            }
            HStack {
                metricChip("Started At", startedAtText)
                metricChip("Speed", engine.speed ?? "--")
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await engine.startLiveStream() }
            } label: {
                HStack {
                    if engine.isBusy { ProgressView().tint(.white) }
                    Text(engine.isBusy ? "Starting..." : "Start Stream").font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Color.green, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(engine.isBusy)

            Button {
                Task { await engine.stopLiveStream() }
            } label: {
                Text("Stop Stream")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(engine.isBusy)
        }
    }

    private var startedAtText: String {
        guard let d = engine.startedAt else { return "--" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: d)
    }

    private func metricChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func liveInput<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
                .padding(14)
                .background(Color(.tertiarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Tab 2: Console (FFmpeg log, real-time)

struct LiveConsoleView: View {
    @ObservedObject var engine: LiveNowEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FFmpeg Console Output").font(.headline)
                Spacer()
                if engine.isBusy { ProgressView().scaleEffect(0.8) }
            }
            HStack(spacing: 8) {
                Button {
                    engine.startMonitor()
                } label: {
                    Label("Live Monitor", systemImage: "play.fill").font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.green.opacity(0.18)).clipShape(Capsule())
                }
                Button {
                    engine.stopMonitor()
                } label: {
                    Label("Stop", systemImage: "stop.fill").font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color.red.opacity(0.18)).clipShape(Capsule())
                }
                Button {
                    engine.consoleLogs = ""
                } label: {
                    Label("Clear", systemImage: "trash").font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(engine.consoleLogs.isEmpty ? "—" : engine.consoleLogs)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .id("LIVE_BOTTOM")
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: engine.consoleLogs) { _ in
                    withAnimation { proxy.scrollTo("LIVE_BOTTOM", anchor: .bottom) }
                }
            }
        }
        .padding()
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { engine.stopMonitor() }
    }
}

// MARK: - Tab 3: Script Automation

struct LiveScriptAutomationView: View {
    @ObservedObject var engine: LiveNowEngine
    @State private var automationCommand = "bash <(curl -s https://...)"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Automated Live Script Setup").font(.headline)

                Text("Quick presets").font(.caption).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(kLiveScriptPresets) { p in
                            Button { automationCommand = p.bashCommand } label: {
                                Text(p.title).font(.caption2.bold())
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Color.orange.opacity(0.18)).clipShape(Capsule())
                            }
                        }
                    }
                }

                Text("One-Liner Execution Script").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $automationCommand)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 90)
                    .padding(6).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)

                Button {
                    Task { await engine.runOneLinerScript(automationCommand) }
                } label: {
                    HStack {
                        if engine.isBusy { ProgressView().tint(.white) }
                        Image(systemName: "play.fill")
                        Text("Execute Live Script").bold()
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(LinearGradient(colors: [Color(red: 1, green: 0.35, blue: 0),
                                                        Color(red: 0.85, green: 0.1, blue: 0.2)],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(engine.isBusy)

                Text("FFmpeg Console Output").font(.caption).foregroundStyle(.gray)
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(engine.consoleLogs.isEmpty ? "—" : engine.consoleLogs)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(10)
                            .id("AUTO_BOTTOM")
                    }
                    .frame(height: 220)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onChange(of: engine.consoleLogs) { _ in
                        withAnimation { proxy.scrollTo("AUTO_BOTTOM", anchor: .bottom) }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Automation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
