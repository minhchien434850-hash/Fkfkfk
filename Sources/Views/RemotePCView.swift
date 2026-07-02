import SwiftUI
import WebKit

// ============================================================================
//  Remote PC (qua cổng Guacamole trên VPS)
//  Anh thêm máy bằng IP + tài khoản + mật khẩu → app gọi REST API của Guacamole
//  tạo kết nối RDP/VNC → mở web điều khiển ngay trong app (giữ đăng nhập).
//  Cần dựng cổng trước: remote-gateway/setup.sh trên VPS.
// ============================================================================

struct GuacMachine: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var proto: String = "rdp"       // rdp | vnc
    var host: String
    var port: String = "3389"
    var username: String = ""
    var password: String = ""
    var connId: String = ""          // id kết nối trong Guacamole (điền sau khi tạo)
}

@MainActor
final class GuacEngine: ObservableObject {
    @Published var gatewayURL: String = ""
    @Published var adminUser: String = "guacadmin"
    @Published var adminPass: String = ""
    @Published var machines: [GuacMachine] = []
    @Published var busy = false
    @Published var message: String?

    private let kURL = "guac_url", kUser = "guac_admin_user", kPass = "guac_admin_pass", kList = "guac_machines"

    init() {
        let d = UserDefaults.standard
        gatewayURL = d.string(forKey: kURL) ?? ""
        adminUser = d.string(forKey: kUser) ?? "guacadmin"
        adminPass = Keychain.load(kPass) ?? ""
        if let raw = d.string(forKey: kList),
           let arr = try? JSONDecoder().decode([GuacMachine].self, from: Data(raw.utf8)) {
            machines = arr
        }
    }

    var configured: Bool {
        !base.isEmpty && !adminUser.isEmpty && !adminPass.isEmpty
    }

    private var base: String {
        var s = gatewayURL.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return "" }
        if !s.hasPrefix("http") { s = "http://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s
    }

    func saveConfig() {
        let d = UserDefaults.standard
        d.set(gatewayURL, forKey: kURL)
        d.set(adminUser, forKey: kUser)
        Keychain.save(kPass, adminPass)
    }

    private func saveMachines() {
        if let data = try? JSONEncoder().encode(machines) {
            UserDefaults.standard.set(String(data: data, encoding: .utf8), forKey: kList)
        }
    }

    func addMachine(_ m: GuacMachine) { machines.append(m); saveMachines() }
    func updateMachine(_ m: GuacMachine) {
        if let i = machines.firstIndex(where: { $0.id == m.id }) { machines[i] = m; saveMachines() }
    }
    func deleteMachine(_ m: GuacMachine) { machines.removeAll { $0.id == m.id }; saveMachines() }

    // MARK: - Guacamole REST API

    private func login() async throws -> (token: String, ds: String) {
        guard let url = URL(string: base + "/api/tokens") else { throw URLError(.badURL) }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "username=\(enc(adminUser))&password=\(enc(adminPass))"
        r.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["authToken"] as? String,
              let ds = obj["dataSource"] as? String else {
            throw NSError(domain: "guac", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Sai địa chỉ cổng hoặc tài khoản Guacamole."])
        }
        return (token, ds)
    }

    /// Tạo (hoặc cập nhật) kết nối cho 1 máy → trả về connId. Mở web điều khiển.
    func connect(_ machine: GuacMachine) async -> URL? {
        guard configured else { message = "Chưa cấu hình cổng Guacamole."; return nil }
        busy = true; message = nil
        defer { busy = false }
        do {
            let (token, ds) = try await login()
            let connId = try await upsertConnection(machine, token: token, ds: ds)
            // Lưu connId lại cho máy
            var m = machine; m.connId = connId; updateMachine(m)
            // URL client: base64(identifier \0 'c' \0 dataSource)
            let idString = "\(connId)\u{0}c\u{0}\(ds)"
            let b64 = Data(idString.utf8).base64EncodedString()
            // Mở kèm token để web tự đăng nhập
            let s = "\(base)/#/client/\(b64)"
            return URL(string: s)
        } catch {
            message = error.localizedDescription
            return nil
        }
    }

    private func upsertConnection(_ m: GuacMachine, token: String, ds: String) async throws -> String {
        // Tìm kết nối cùng tên để tránh trùng
        if let existing = try await findConnection(named: m.name, token: token, ds: ds) {
            try await putConnection(id: existing, m: m, token: token, ds: ds)
            return existing
        }
        return try await postConnection(m, token: token, ds: ds)
    }

    private func findConnection(named name: String, token: String, ds: String) async throws -> String? {
        guard let url = URL(string: "\(base)/api/session/data/\(ds)/connections?token=\(enc(token))") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for (id, v) in map {
            if let dict = v as? [String: Any], (dict["name"] as? String) == name { return id }
        }
        return nil
    }

    private func connectionBody(_ m: GuacMachine) -> [String: Any] {
        var params: [String: String] = [
            "hostname": m.host.trimmingCharacters(in: .whitespaces),
            "port": m.port.trimmingCharacters(in: .whitespaces),
            "username": m.username,
            "password": m.password,
        ]
        if m.proto == "rdp" {
            params["security"] = "any"
            params["ignore-cert"] = "true"
            params["resize-method"] = "display-update"
        }
        return [
            "parentIdentifier": "ROOT",
            "name": m.name,
            "protocol": m.proto,
            "parameters": params,
            "attributes": [:],
        ]
    }

    private func postConnection(_ m: GuacMachine, token: String, ds: String) async throws -> String {
        guard let url = URL(string: "\(base)/api/session/data/\(ds)/connections?token=\(enc(token))") else {
            throw URLError(.badURL)
        }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: connectionBody(m))
        let (data, resp) = try await URLSession.shared.data(for: r)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["identifier"] as? String else {
            throw NSError(domain: "guac", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Không tạo được kết nối trong Guacamole."])
        }
        return id
    }

    private func putConnection(id: String, m: GuacMachine, token: String, ds: String) async throws {
        guard let url = URL(string: "\(base)/api/session/data/\(ds)/connections/\(id)?token=\(enc(token))") else { return }
        var r = URLRequest(url: url)
        r.httpMethod = "PUT"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: connectionBody(m))
        _ = try? await URLSession.shared.data(for: r)
    }

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    var autoLoginScript: String {
        let u = adminUser.replacingOccurrences(of: "'", with: "\\'")
        let p = adminPass.replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(){
          function fill(){
            var uu=document.querySelector('input[name=username],input[ng-model*="username"]');
            var pp=document.querySelector('input[type=password],input[ng-model*="password"]');
            if(uu&&pp){
              var set=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
              set.call(uu,'\(u)'); uu.dispatchEvent(new Event('input',{bubbles:true}));
              set.call(pp,'\(p)'); pp.dispatchEvent(new Event('input',{bubbles:true}));
              var f=uu.closest('form'); var b=document.querySelector('button[type=submit],input[type=submit]');
              setTimeout(function(){ if(b){b.click();} else if(f){f.requestSubmit?f.requestSubmit():f.submit();} },300);
            } else { setTimeout(fill,600); }
          }
          setTimeout(fill,500);
        })();
        """
    }
}

struct RemotePCView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var guac = GuacEngine()

    @State private var showConfig = false
    @State private var showAdd = false
    @State private var editing: GuacMachine?
    @State private var openTarget: GuacOpenTarget?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KHeroHeader(icon: "display",
                                title: "Remote PC",
                                subtitle: store.t("Thêm máy bằng IP + tài khoản + mật khẩu",
                                                  "Add PCs by IP + username + password"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Cổng Guacamole
                Section(store.t("Cổng điều khiển (VPS)", "Gateway (VPS)")) {
                    HStack {
                        Image(systemName: guac.configured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(guac.configured ? .green : .orange)
                        Text(guac.configured ? (guac.gatewayURL) : store.t("Chưa cấu hình cổng", "Gateway not set"))
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Button(store.t("Cấu hình", "Configure")) { showConfig = true }.font(.caption.bold())
                    }
                    if !guac.configured {
                        Text(store.t("Cần dựng cổng trên VPS trước (remote-gateway/setup.sh), rồi bấm Cấu hình.",
                                     "Set up the gateway on your VPS first, then Configure."))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Danh sách máy
                Section(store.t("Máy của bạn", "Your PCs")) {
                    if guac.machines.isEmpty {
                        Text(store.t("Chưa có máy. Bấm ➕ để thêm.", "No PCs. Tap ➕ to add."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(guac.machines) { m in
                        Button {
                            Task { if let u = await guac.connect(m) { openTarget = GuacOpenTarget(url: u) } }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.proto == "vnc" ? "display.2" : "pc")
                                    .font(.title3).foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                    Text("\(m.proto.uppercased()) · \(m.host):\(m.port)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if guac.busy { ProgressView() }
                                else { Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent) }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { guac.deleteMachine(m) } label: {
                                Image(systemName: "trash")
                            }
                            Button { editing = m } label: { Image(systemName: "pencil") }.tint(.blue)
                        }
                    }
                }

                if let msg = guac.message {
                    Section { Text(msg).font(.caption).foregroundStyle(.red) }
                }

                Section(store.t("Hướng dẫn", "Guide")) {
                    Text(store.t("1. Trên VPS chạy: remote-gateway/setup.sh\n2. Bấm Cấu hình, nhập http://IP_VPS:8080 + tài khoản guacadmin.\n3. Bấm ➕ thêm máy: nhập IP + user + pass của máy cần điều khiển.\n4. Bấm vào máy để điều khiển ngay trong app.",
                                 "1. Run remote-gateway/setup.sh on VPS.\n2. Configure http://VPS_IP:8080 + guacadmin.\n3. Add a PC with its IP + user + pass.\n4. Tap it to control."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Remote PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill") }
                        .disabled(!guac.configured)
                }
            }
            .sheet(isPresented: $showConfig) { configSheet }
            .sheet(isPresented: $showAdd) {
                GuacMachineForm(machine: nil) { guac.addMachine($0) }
            }
            .sheet(item: $editing) { m in
                GuacMachineForm(machine: m) { guac.updateMachine($0) }
            }
            .fullScreenCover(item: $openTarget) { t in
                GuacSessionView(url: t.url, loginScript: guac.autoLoginScript)
            }
        }
    }

    private var configSheet: some View {
        NavigationStack {
            Form {
                Section(store.t("Địa chỉ cổng (VPS)", "Gateway URL")) {
                    TextField("http://IP_VPS:8080", text: $guac.gatewayURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                }
                Section("Guacamole admin") {
                    TextField("guacadmin", text: $guac.adminUser)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(store.t("Mật khẩu Guacamole", "Guacamole password"), text: $guac.adminPass)
                }
                Text(store.t("Đây là tài khoản đăng nhập cổng Guacamole (mặc định guacadmin), KHÔNG phải mật khẩu của máy cần điều khiển.",
                             "This is the Guacamole gateway login (default guacadmin), NOT the target PC password."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .navigationTitle(store.t("Cấu hình cổng", "Configure gateway"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Lưu", "Save")) { guac.saveConfig(); showConfig = false }
                }
            }
        }
    }
}

// Bọc URL để dùng fullScreenCover(item:) — không mở rộng URL toàn cục
struct GuacOpenTarget: Identifiable { let id = UUID(); let url: URL }

// MARK: - Form thêm/sửa máy

struct GuacMachineForm: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let onSave: (GuacMachine) -> Void
    @State private var m: GuacMachine

    init(machine: GuacMachine?, onSave: @escaping (GuacMachine) -> Void) {
        self.onSave = onSave
        _m = State(initialValue: machine ?? GuacMachine(name: "", host: ""))
    }

    private var canSave: Bool {
        !m.name.trimmingCharacters(in: .whitespaces).isEmpty && !m.host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Thông tin máy", "PC info")) {
                    TextField(store.t("Tên gợi nhớ (vd: Máy game)", "Name (e.g. Game PC)"), text: $m.name)
                    Picker(store.t("Loại", "Type"), selection: $m.proto) {
                        Text("RDP (Windows)").tag("rdp")
                        Text("VNC").tag("vnc")
                    }.pickerStyle(.segmented)
                    TextField(store.t("IP máy (vd 42.119.44.44)", "IP (e.g. 42.119.44.44)"), text: $m.host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.numbersAndPunctuation)
                    TextField(store.t("Cổng (RDP 3389, hoặc số nhà cung cấp cho)", "Port (RDP 3389)"), text: $m.port)
                        .keyboardType(.numberPad)
                }
                Section(store.t("Đăng nhập máy", "PC login")) {
                    TextField(store.t("Tài khoản", "Username"), text: $m.username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(store.t("Mật khẩu", "Password"), text: $m.password)
                }
            }
            .navigationTitle(store.t("Thêm máy", "Add PC"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(store.t("Huỷ", "Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Lưu", "Save")) {
                        m.name = m.name.trimmingCharacters(in: .whitespaces)
                        m.host = m.host.trimmingCharacters(in: .whitespaces)
                        if m.port.isEmpty { m.port = m.proto == "vnc" ? "5900" : "3389" }
                        onSave(m); dismiss()
                    }.disabled(!canSave)
                }
            }
        }
    }
}

// MARK: - Phiên điều khiển (WKWebView + tự đăng nhập Guacamole)

struct GuacSessionView: View {
    let url: URL
    let loginScript: String
    @Environment(\.dismiss) var dismiss
    @State private var loading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            GuacWebView(url: url, loginScript: loginScript, loading: $loading)
                .ignoresSafeArea(edges: .bottom)
            if loading {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Đang kết nối tới máy...").font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.ultraThinMaterial)
                Spacer()
            }
        }
    }
}

struct GuacWebView: UIViewRepresentable {
    let url: URL
    let loginScript: String
    @Binding var loading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        // Tự điền đăng nhập Guacamole nếu gặp trang login
        let script = WKUserScript(source: loginScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        cfg.userContentController.addUserScript(script)
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        wv.scrollView.maximumZoomScale = 6
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: GuacWebView
        init(_ p: GuacWebView) { parent = p }
        func webView(_ wv: WKWebView, didFinish n: WKNavigation!) { parent.loading = false }
        func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) { parent.loading = false }
        func webView(_ wv: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) { parent.loading = false }
    }
}
