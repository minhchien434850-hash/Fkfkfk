import SwiftUI

// ============================================================================
//  Remote Server Tool — SSH · SFTP · Automated Script Executor
//  Kết nối tới VPS QUA máy chủ Kenios (backend dùng asyncssh làm cầu nối).
//  App gửi Host/Username/Password + lệnh → backend SSH tới VPS đích và truyền
//  log về theo thời gian thực. Giao diện điều khiển bằng tiếng Anh theo yêu cầu.
// ============================================================================

// MARK: - Models

enum AppConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case failed(String)
}

struct SFTPFileItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let size: Int

    /// Các định dạng có thể CHẠY được trên Linux.
    static let runnableExtensions = [".sh", ".py", ".js", ".go", ".pl", ".rb", ".jar"]

    /// true nếu là FILE (không phải thư mục) và đuôi nằm trong danh sách chạy được.
    var isRunnableOnVPS: Bool {
        guard !isDirectory else { return false }
        let lower = name.lowercased()
        return SFTPFileItem.runnableExtensions.contains { lower.hasSuffix($0) }
    }

    var iconName: String {
        if isDirectory { return "folder.fill" }
        if isRunnableOnVPS { return "bolt.square.fill" }
        return "doc.text.fill"
    }
}

struct ScriptPreset: Identifiable {
    let id = UUID()
    let title: String
    let bashCommand: String
}

/// Các lệnh one-liner mẫu để bấm chạy nhanh.
let kScriptPresets: [ScriptPreset] = [
    ScriptPreset(title: "Update Kenios backend",
                 bashCommand: "bash <(curl -s https://raw.githubusercontent.com/minhchien434850-hash/Fkfkfk/claude/read-branch-file-2lxkte/capnhat-vps.sh)"),
    ScriptPreset(title: "Service status",
                 bashCommand: "systemctl status kenios --no-pager | head -n 25"),
    ScriptPreset(title: "Restart service",
                 bashCommand: "systemctl restart kenios && echo '== restarted =='"),
    ScriptPreset(title: "Live logs (last 40 lines)",
                 bashCommand: "journalctl -u kenios -n 40 --no-pager"),
    ScriptPreset(title: "Disk usage",
                 bashCommand: "df -h")
]

// MARK: - Engine (talks to Kenios backend SSH proxy)

private struct SFTPListResponse: Decodable {
    let path: String
    let items: [Item]
    struct Item: Decodable { let name: String; let type: String; let size: Int }
}

@MainActor
final class RemoteServerEngine: ObservableObject {
    // Connection config
    @Published var host = ""
    @Published var port = "22"
    @Published var username = "root"
    @Published var password = ""

    @Published var state: AppConnectionState = .idle
    @Published var errorMessage: String?

    // Terminal / Script console
    @Published var consoleLogs = ""
    @Published var isExecuting = false

    // SFTP browser
    @Published var currentPath = "/root"
    @Published var files: [SFTPFileItem] = []
    @Published var sftpError: String?
    @Published var loadingFiles = false

    private let baseURL: String
    private let token: String

    init(baseURL: String, token: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.token = token
    }

    private func request(_ path: String) -> URLRequest? {
        guard let url = URL(string: baseURL + path) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 600
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private var credsJSON: [String: Any] {
        ["host": host.trimmingCharacters(in: .whitespaces),
         "port": Int(port) ?? 22,
         "username": username.trimmingCharacters(in: .whitespaces),
         "password": password]
    }

    // MARK: Connect (validate by running a trivial command)

    func connect() async {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty,
              !username.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Please fill Host and Username."
            return
        }
        state = .connecting
        errorMessage = nil
        do {
            let out = try await runCommandCollect("echo KENIOS_SSH_OK")
            if out.contains("KENIOS_SSH_OK") {
                state = .connected
                consoleLogs = "Connected to \(host).\n"
                await listDirectory(currentPath)
            } else {
                state = .failed("Unexpected response.")
                errorMessage = out.isEmpty ? "No response from server." : out
            }
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func disconnect() {
        state = .idle
        consoleLogs = ""
        files = []
        password = ""
        errorMessage = nil
        sftpError = nil
    }

    // MARK: Execute one-liner with REAL-TIME streaming output

    func runOneLinerScript(_ command: String) async {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        guard state == .connected else {
            consoleLogs += "Execution Error: Not connected.\n"
            return
        }
        guard var req = request("/ssh/exec") else {
            consoleLogs += "Execution Error: Invalid server URL.\n"
            return
        }
        isExecuting = true
        consoleLogs += "\n$ \(cmd)\n"
        var body = credsJSON
        body["command"] = cmd
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                var msg = ""
                for try await line in bytes.lines { msg += line + "\n" }
                consoleLogs += "Execution Error: \(msg.isEmpty ? "HTTP \(http.statusCode)" : msg)\n"
                isExecuting = false
                return
            }
            for try await line in bytes.lines {
                consoleLogs += line + "\n"
            }
        } catch {
            consoleLogs += "Execution Error: \(error.localizedDescription)\n"
        }
        isExecuting = false
    }

    /// Chạy lệnh và gom toàn bộ output (dùng cho kiểm tra kết nối).
    private func runCommandCollect(_ command: String) async throws -> String {
        guard var req = request("/ssh/exec") else { throw URLError(.badURL) }
        var body = credsJSON
        body["command"] = command
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let text = String(data: data, encoding: .utf8) ?? ""
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(domain: "ssh", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "HTTP \(http.statusCode)" : text])
        }
        return text
    }

    // MARK: SFTP

    func listDirectory(_ path: String) async {
        guard var req = request("/ssh/list") else { return }
        loadingFiles = true
        sftpError = nil
        var body = credsJSON
        body["path"] = path
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                sftpError = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                loadingFiles = false
                return
            }
            let decoded = try JSONDecoder().decode(SFTPListResponse.self, from: data)
            currentPath = decoded.path
            files = decoded.items
                .map { SFTPFileItem(name: $0.name, isDirectory: $0.type == "dir", size: $0.size) }
                .sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
                    return a.name.lowercased() < b.name.lowercased()
                }
        } catch {
            sftpError = error.localizedDescription
        }
        loadingFiles = false
    }

    func openItem(_ item: SFTPFileItem) async {
        guard item.isDirectory else { return }
        await listDirectory(joinPath(currentPath, item.name))
    }

    func goUp() async {
        guard currentPath != "/" else { return }
        let comps = currentPath.split(separator: "/").dropLast()
        let parent = "/" + comps.joined(separator: "/")
        await listDirectory(parent == "/" ? "/" : parent)
    }

    func deleteFiles(_ items: [SFTPFileItem]) async {
        for item in items where !item.isDirectory {
            guard var req = request("/ssh/delete") else { continue }
            var body = credsJSON
            body["path"] = joinPath(currentPath, item.name)
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
        await listDirectory(currentPath)
    }

    private func joinPath(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }
}

// MARK: - Root (KeniosExploreView entry)

struct RemoteServerRootView: View {
    @StateObject private var engine: RemoteServerEngine

    init(baseURL: String, token: String) {
        _engine = StateObject(wrappedValue: RemoteServerEngine(baseURL: baseURL, token: token))
    }

    var body: some View {
        Group {
            if engine.state == .connected {
                RemoteWorkspaceView(engine: engine)
            } else {
                NavigationStack { QuickConnectView(engine: engine) }
            }
        }
    }
}

// MARK: - QuickConnectView (English login form)

struct QuickConnectView: View {
    @ObservedObject var engine: RemoteServerEngine

    private var canSubmit: Bool {
        !engine.host.trimmingCharacters(in: .whitespaces).isEmpty
            && !engine.username.trimmingCharacters(in: .whitespaces).isEmpty
            && !engine.password.isEmpty
            && engine.state != .connecting
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                connectionFormSection
                connectionStatusSection
                actionSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Quick Connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remote Server Tool")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            Text("Securely connect to your VPS and open the remote workspace.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connection Information")
                .font(.headline)

            VStack(spacing: 14) {
                labeledField("Host or IP Address", systemImage: "network") {
                    TextField("192.168.1.10 or example.com", text: $engine.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                labeledField("Port", systemImage: "number") {
                    TextField("22", text: $engine.port).keyboardType(.numberPad)
                }
                labeledField("Username", systemImage: "person.fill") {
                    TextField("root", text: $engine.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                labeledField("Password", systemImage: "lock.fill") {
                    SecureField("Enter password", text: $engine.password)
                }
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var connectionStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connection Status")
                .font(.headline)

            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                    if engine.state == .connected {
                        Text("\(engine.username)@\(engine.host)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let err = engine.errorMessage {
                        Text(err)
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No active connection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await engine.connect() }
            } label: {
                HStack {
                    if engine.state == .connecting { ProgressView().tint(.white) }
                    Text(engine.state == .connecting ? "Connecting..." : "Connect and Open Workspace")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 16)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(colors: canSubmit ? [.blue, .cyan] : [.gray, .gray],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)

            Text("Credentials are sent over HTTPS to your Kenios server, which connects to the target VPS on your behalf. They are not stored.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var statusTitle: String {
        switch engine.state {
        case .idle:       return "Idle"
        case .connecting: return "Connecting"
        case .connected:  return "Connected"
        case .failed:     return "Failed"
        }
    }

    private var statusColor: Color {
        switch engine.state {
        case .idle:       return .gray
        case .connecting: return .orange
        case .connected:  return .green
        case .failed:     return .red
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, systemImage: String,
                                             @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                content()
            }
            .padding(14)
            .background(Color(.tertiarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Workspace (3 Tabs)

struct RemoteWorkspaceView: View {
    @ObservedObject var engine: RemoteServerEngine

    var body: some View {
        NavigationStack {
            TabView {
                TerminalView(engine: engine)
                    .tabItem { Label("Terminal", systemImage: "terminal") }
                SFTPBrowserView(engine: engine)
                    .tabItem { Label("Files", systemImage: "folder") }
                ScriptExecutorView(engine: engine)
                    .tabItem { Label("Scripts", systemImage: "bolt.fill") }
            }
            .navigationTitle(engine.host)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Disconnect") { engine.disconnect() }
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

// MARK: - Console (shared, auto-scrolling)

struct RemoteConsoleView: View {
    let text: String
    var height: CGFloat = 250

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "—" : text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
                    .id("CONSOLE_BOTTOM")
            }
            .frame(height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: text) { _ in
                withAnimation { proxy.scrollTo("CONSOLE_BOTTOM", anchor: .bottom) }
            }
        }
    }
}

// MARK: - Tab 1: Terminal

struct TerminalView: View {
    @ObservedObject var engine: RemoteServerEngine
    @State private var commandInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Terminal Console").font(.headline)
            HStack {
                TextField("Type a command, e.g. ls -la", text: $commandInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                    let c = commandInput
                    commandInput = ""
                    Task { await engine.runOneLinerScript(c) }
                } label: {
                    Image(systemName: "paperplane.fill").font(.title3)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(engine.isExecuting || commandInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Text("Terminal Console Output").font(.caption).foregroundStyle(.gray)
                Spacer()
                if engine.isExecuting { ProgressView().scaleEffect(0.8) }
                Button { engine.consoleLogs = "" } label: {
                    Label("Clear", systemImage: "trash").font(.caption2)
                }
            }
            RemoteConsoleView(text: engine.consoleLogs, height: 360)
            Spacer(minLength: 0)
        }
        .padding()
    }
}

// MARK: - Tab 2: SFTP Browser (runnable highlight)

struct SFTPBrowserView: View {
    @ObservedObject var engine: RemoteServerEngine
    @State private var selectMode = false
    @State private var selected: Set<UUID> = []
    @State private var pathInput = ""
    private let cols = [GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { Task { await engine.goUp() } } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title3)
                }
                .disabled(engine.currentPath == "/")
                Text(engine.currentPath)
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await engine.listDirectory(engine.currentPath) }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.caption.bold())
                }
                Button(selectMode ? "Done" : "Select") {
                    selectMode.toggle()
                    if !selectMode { selected.removeAll() }
                }.font(.caption.bold())
            }
            .padding(.horizontal)

            HStack {
                TextField("Go to path, e.g. /var/www/html", text: $pathInput)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.caption)
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button("Go") {
                    let p = pathInput.trimmingCharacters(in: .whitespaces)
                    if !p.isEmpty { Task { await engine.listDirectory(p) } }
                }.font(.caption.bold())
            }
            .padding(.horizontal)

            if let err = engine.sftpError {
                Text(err).font(.caption2).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }

            if engine.loadingFiles {
                ProgressView().padding()
            }

            ScrollView {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(engine.files) { item in
                        fileCell(item)
                            .onTapGesture {
                                if selectMode {
                                    if item.isDirectory { return }
                                    if selected.contains(item.id) { selected.remove(item.id) }
                                    else { selected.insert(item.id) }
                                } else {
                                    Task { await engine.openItem(item) }
                                }
                            }
                    }
                }
                .padding()
            }

        }
        .padding(.top, 8)
        // Material Bottom Action Bar — kính mờ, trượt lên khi chọn > 0 mục.
        .overlay(alignment: .bottom) {
            if selectMode && !selected.isEmpty {
                bottomActionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selected.count)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: selectMode)
    }

    private var bottomActionBar: some View {
        HStack(spacing: 14) {
            Button { selected.removeAll() } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            Text("\(selected.count) selected").font(.subheadline.bold())
            Spacer()
            Button {
                let items = engine.files.filter { selected.contains($0.id) }
                selected.removeAll()
                Task { await engine.deleteFiles(items) }
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(Color.red).clipShape(Capsule())
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        .padding(.horizontal, 14).padding(.bottom, 12)
    }

    private func fileCell(_ item: SFTPFileItem) -> some View {
        let isSel = selected.contains(item.id)
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.iconName)
                    .font(.system(size: 30))
                    .foregroundStyle(item.isDirectory ? Color.blue
                                     : (item.isRunnableOnVPS ? Color.green : Color.gray))
                    .frame(maxWidth: .infinity).frame(height: 54)
                // Badge tia sét cho file chạy được
                if item.isRunnableOnVPS {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                        .padding(4)
                }
                if selectMode && !item.isDirectory {
                    Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSel ? .green : .secondary)
                        .padding(4)
                }
            }
            Text(item.name)
                .font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                .frame(height: 30)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.isRunnableOnVPS ? Color.green : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Tab 3: Script Executor (one-liner + live log)

struct ScriptExecutorView: View {
    @ObservedObject var engine: RemoteServerEngine
    @State private var commandInput = "bash <(curl -s https://...)"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Automated Script Executor").font(.headline)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick presets").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(kScriptPresets) { p in
                                Button { commandInput = p.bashCommand } label: {
                                    Text(p.title).font(.caption2.bold())
                                        .padding(.horizontal, 10).padding(.vertical, 7)
                                        .background(Color.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                Text("Script URL / Command").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $commandInput)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(height: 90)
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                Button {
                    Task { await engine.runOneLinerScript(commandInput) }
                } label: {
                    HStack {
                        if engine.isExecuting { ProgressView().tint(.white) }
                        Image(systemName: "play.fill")
                        Text("Execute Script").bold()
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(LinearGradient(colors: [.blue, .purple],
                                               startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(engine.isExecuting)

                HStack {
                    Text("Terminal Console Output").font(.caption).foregroundStyle(.gray)
                    Spacer()
                    Button { engine.consoleLogs = "" } label: {
                        Label("Clear", systemImage: "trash").font(.caption2)
                    }
                }
                RemoteConsoleView(text: engine.consoleLogs, height: 280)
            }
            .padding()
        }
    }
}
