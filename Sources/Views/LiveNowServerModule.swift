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

    // Console
    @Published var consoleLogs = ""
    @Published var isBusy = false

    private let baseURL: String
    private let token: String
    private var monitorTask: Task<Void, Never>?
    private let logPath = "/root/kenios_live.log"

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
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
        password = ""
        connectError = nil
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
    }

    func stopLiveStream() async {
        await runStreaming("pkill -f ffmpeg && echo 'Live stream stopped.' || echo 'No active stream.'")
        streamStatus = .offline
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
        isBusy = true
        consoleLogs += "\n$ \(command.prefix(120))\n"
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                var msg = ""
                for try await line in bytes.lines { msg += line + "\n" }
                consoleLogs += "Execution Error: \(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)\n"
                isBusy = false
                return
            }
            for try await line in bytes.lines {
                if checkCancel && Task.isCancelled { break }
                consoleLogs += line + "\n"
                if consoleLogs.count > 60000 {
                    consoleLogs = String(consoleLogs.suffix(40000))
                }
            }
        } catch is CancellationError {
            consoleLogs += "\n[monitor stopped]\n"
        } catch {
            consoleLogs += "Execution Error: \(error.localizedDescription)\n"
        }
        isBusy = false
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

                Text("Credentials are sent over HTTPS to your Kenios server, which controls the target VPS. They are not stored.")
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Live Status:").font(.subheadline.bold())
                    Text(engine.streamStatus.label)
                        .font(.subheadline.bold())
                        .foregroundStyle(engine.streamStatus.color)
                    Circle().fill(engine.streamStatus.color).frame(width: 10, height: 10)
                    Spacer()
                    Button { Task { await engine.refreshStatus() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Source File or URL")
                    TextField("/root/live_source.mp4 or https://...", text: $engine.sourceInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    fieldLabel("Target Stream URL")
                    TextField("rtmp://a.rtmp.youtube.com/live2", text: $engine.streamUrl)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    fieldLabel("Stream Key")
                    SecureField("x-xxxx-xxxx-xxxx-xxxx", text: $engine.streamKey)
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    Task { await engine.startLiveStream() }
                } label: {
                    HStack {
                        if engine.isBusy { ProgressView().tint(.white) }
                        Image(systemName: "dot.radiowaves.left.and.right")
                        Text("START LIVE STREAM").bold()
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(engine.isBusy)

                Button {
                    Task { await engine.stopLiveStream() }
                } label: {
                    Label("STOP STREAM", systemImage: "stop.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("FFmpeg loops the source and pushes it to the RTMP target. Requires FFmpeg installed on the VPS (use the Automation tab → Install FFmpeg).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Engine: \(engine.host)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fieldLabel(_ t: String) -> some View {
        Text(t).font(.caption.bold()).foregroundStyle(.secondary)
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
