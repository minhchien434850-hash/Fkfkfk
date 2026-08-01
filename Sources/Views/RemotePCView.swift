import SwiftUI
import UIKit

// ============================================================================
//  §11 — Windows App / Điều khiển PC từ xa (relay qua KENIOS)
//  Không cần nhập VPS: app dùng luôn máy chủ KENIOS. Chạy agent (pc-agent) trên
//  PC, đăng nhập cùng tài khoản → máy tự hiện ở đây để điều khiển. Có cả bản Web.
// ============================================================================

// Kết nối PC đã lưu (kiểu "Add PC" của Microsoft): tên + địa chỉ + tài khoản KENIOS.
// Kết nối qua hệ thống agent KENIOS (đăng nhập tài khoản để lấy máy online của tài khoản đó).
struct SavedPC: Identifiable, Codable, Hashable {
    var id = UUID()
    var friendlyName: String = ""   // Friendly Name (tuỳ chọn)
    var host: String = ""           // Hostname / IP (nhãn · lọc đúng máy)
    var account: String = ""        // Tài khoản KENIOS mà pc-agent đăng nhập
    var password: String = ""       // Mật khẩu KENIOS (để lấy máy online của tài khoản)
    var adminMode: Bool = false
    var swapMouse: Bool = false
    var title: String { friendlyName.isEmpty ? (host.isEmpty ? account : host) : friendlyName }
}

enum SavedPCStore {
    private static let key = "kenios_saved_pcs"
    static func load() -> [SavedPC] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([SavedPC].self, from: d) else { return [] }
        return arr
    }
    static func save(_ arr: [SavedPC]) {
        if let d = try? JSONEncoder().encode(arr) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct RemotePCView: View {
    @EnvironmentObject var store: AppStore
    @State private var pcs: [PCAgent] = []
    @State private var loading = true
    @State private var openPC: PCAgent?
    @State private var openAPI: APIClient?          // token tài khoản đã lưu (nil = tài khoản hiện tại)
    // Add PC (máy đã lưu)
    @State private var savedPCs: [SavedPC] = SavedPCStore.load()
    @State private var showAddPC = false
    @State private var editingPC: SavedPC?
    @State private var connecting = false
    @State private var connectMsg: String?
    // §11b — Kết nối máy thuê bằng IP + user + pass (cầu nối RDP máy chủ)
    @State private var showRDP = false
    @State private var rdpOpen: RDPOpen?

    private var webURL: String {
        var s = store.baseURL.trimmingCharacters(in: .whitespaces)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        if s.hasSuffix("/") { s = String(s.dropLast()) }
        return s + "/pc"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    KHeroHeader(icon: "pc", title: "Windows App",
                                subtitle: store.t("Điều khiển PC từ xa — chuột, bàn phím, media (mượt, thời gian thực)",
                                                  "Remote control — mouse, keyboard, media (smooth, real-time)"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section(store.t("Máy của bạn", "Your PCs")) {
                    if loading {
                        ProgressView()
                    } else if pcs.isEmpty {
                        Text(store.t("Chưa có máy. Chạy agent trên PC (xem hướng dẫn dưới) rồi bấm Tải lại.",
                                     "No PCs yet. Run the agent on your PC (see guide) then Reload."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(pcs) { p in
                        Button {
                            if p.online { openPC = p }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: p.os == "Darwin" ? "laptopcomputer" : "pc")
                                    .font(.title3).foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.subheadline.bold()).foregroundStyle(.primary)
                                    HStack(spacing: 5) {
                                        Circle().fill(p.online ? .green : .orange).frame(width: 8, height: 8)
                                        Text(p.online ? store.t("Đang online", "Online")
                                                       : store.t("Ngoại tuyến", "Offline"))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if p.online { Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent) }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { try? await store.api.pcDelete(agentId: p.agentId); await reload() }
                            } label: { Image(systemName: "trash") }
                        }
                    }
                }

                // §11b — Kết nối máy thuê chỉ bằng IP + tài khoản (không cần cài agent)
                Section {
                    Button { showRDP = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "network")
                                .font(.title3).foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.t("Kết nối bằng IP + tài khoản", "Connect by IP + account"))
                                    .font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(store.t("Cho máy thuê (VPS) — chỉ nhập IP/user/pass",
                                             "For a rented PC (VPS) — just enter IP/user/pass"))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(store.t("Máy thuê (RDP thẳng)", "Rented PC (direct RDP)"))
                } footer: {
                    Text(store.t("Máy chủ KENIOS kết nối RDP tới máy thuê giúp bạn — không cần cài gì lên máy đó. Máy cần có IP công khai và bật Remote Desktop.",
                                 "The KENIOS server makes the RDP connection for you — nothing to install on that PC. It needs a public IP with Remote Desktop enabled."))
                        .font(.caption2)
                }

                // Add PC — máy đã lưu (đăng nhập bằng tài khoản như app Microsoft)
                Section {
                    if connecting { HStack { ProgressView(); Text(store.t("Đang kết nối…", "Connecting…")).font(.caption) } }
                    if let connectMsg { Text(connectMsg).font(.caption).foregroundStyle(.red) }
                    ForEach(savedPCs) { s in
                        Button { connectSaved(s) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .font(.title3).foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.purple).clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                    Text(s.account.isEmpty ? store.t("Tài khoản hiện tại", "Current account") : s.account)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { removeSaved(s) } label: { Image(systemName: "trash") }
                            Button { editingPC = s } label: { Image(systemName: "pencil") }.tint(.blue)
                        }
                    }
                    Button { showAddPC = true } label: {
                        Label(store.t("Thêm PC (Add PC)", "Add PC"), systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                    }
                } header: {
                    Text(store.t("Máy đã lưu (Add PC)", "Saved PCs (Add PC)"))
                } footer: {
                    Text(store.t("Nhập tên máy + tài khoản KENIOS mà PC đã đăng nhập. Bấm để đăng nhập và điều khiển máy online của tài khoản đó.",
                                 "Enter the PC name + the KENIOS account the PC signed in with. Tap to log in and control that account's online PC."))
                        .font(.caption2)
                }

                Section(store.t("Dùng trên Web", "Use on Web")) {
                    HStack {
                        Image(systemName: "globe").foregroundStyle(Theme.accent)
                        Text(webURL).font(.caption.monospaced()).lineLimit(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = webURL
                        } label: { Image(systemName: "doc.on.doc").font(.caption) }
                    }
                    Text(store.t("Mở địa chỉ trên bằng trình duyệt bất kỳ → đăng nhập tài khoản KENIOS → điều khiển như app.",
                                 "Open that URL in any browser → sign in with your KENIOS account → control like the app."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Cách bật máy để điều khiển", "How to enable a PC")) {
                    Text(store.t("1. Trên PC cần điều khiển: chạy agent trong thư mục pc-agent (Windows: start-windows.bat; macOS: start-mac.command).\n2. Nhập Tài khoản + Mật khẩu KENIOS (giống app).\n3. Máy hiện ở mục \"Máy của bạn\" — bấm để điều khiển. Không cần nhập IP/VPS.",
                                 "1. On the target PC: run the agent in pc-agent (Windows: start-windows.bat; macOS: start-mac.command).\n2. Enter your KENIOS username + password.\n3. The PC appears above — tap to control. No IP/VPS needed."))
                        .font(.caption2).foregroundStyle(.secondary)
                    NavigationLink {
                        WinAppArchitectureDetail()
                    } label: {
                        Label(store.t("Xem kiến trúc hệ thống", "View system architecture"), systemImage: "point.3.filled.connected.trianglepath.dotted")
                            .font(.caption.bold())
                    }
                }
            }
            .navigationTitle("Windows App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddPC = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .fullScreenCover(item: $openPC) { p in
                PCControllerView(agent: p, apiOverride: openAPI).environmentObject(store)
            }
            .sheet(isPresented: $showAddPC) {
                AddRemotePCView { newPC in
                    savedPCs.append(newPC); SavedPCStore.save(savedPCs)
                }.environmentObject(store)
            }
            .sheet(item: $editingPC) { pc in
                AddRemotePCView(existing: pc) { updated in
                    if let i = savedPCs.firstIndex(where: { $0.id == updated.id }) {
                        savedPCs[i] = updated; SavedPCStore.save(savedPCs)
                    }
                }.environmentObject(store)
            }
            .sheet(isPresented: $showRDP) {
                RDPConnectView { open in
                    showRDP = false
                    // Chờ sheet đóng hẳn rồi mới mở màn điều khiển (tránh xung đột trình bày).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rdpOpen = open }
                }.environmentObject(store)
            }
            .fullScreenCover(item: $rdpOpen) { o in
                PCControllerView(agent: PCAgent(agentId: o.rid, name: o.host, os: "Windows", online: true),
                                 rdpId: o.rid).environmentObject(store)
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        pcs = (try? await store.api.pcMine()) ?? []
    }

    private func removeSaved(_ s: SavedPC) {
        savedPCs.removeAll { $0.id == s.id }; SavedPCStore.save(savedPCs)
    }

    // Đăng nhập tài khoản đã lưu → lấy máy online của tài khoản đó → mở màn điều khiển.
    private func connectSaved(_ s: SavedPC) {
        connecting = true; connectMsg = nil
        Task {
            defer { connecting = false }
            do {
                let api: APIClient
                if s.account.isEmpty {
                    api = store.api   // dùng tài khoản đang đăng nhập
                } else {
                    let auth = try await store.api.login(s.account, s.password)
                    api = APIClient(baseURL: store.baseURL, token: auth.token)
                }
                let list = (try? await api.pcMine()) ?? []
                let online = list.filter { $0.online }
                // Ưu tiên máy trùng tên/host đã đặt; nếu không, lấy máy online đầu tiên.
                let target = online.first(where: { $0.name.caseInsensitiveCompare(s.host) == .orderedSame })
                    ?? online.first
                guard let agent = target else {
                    connectMsg = store.t("Chưa thấy máy online cho tài khoản này. Hãy chạy pc-agent trên PC bằng đúng tài khoản rồi thử lại.",
                                         "No online PC for this account yet. Run pc-agent on the PC with this account, then retry.")
                    return
                }
                openAPI = (s.account.isEmpty ? nil : api)
                openPC = agent
            } catch {
                connectMsg = store.t("Đăng nhập thất bại: ", "Login failed: ") + error.localizedDescription
            }
        }
    }
}

// MARK: - Engine điều khiển (quản lý gửi lệnh mượt + ảnh màn hình)

@MainActor
final class PCEngine: ObservableObject {
    private(set) var api: APIClient
    let agentId: String
    @Published var screen: UIImage?
    @Published var online = true
    @Published var speed: Double = 2.5

    private var accDX: CGFloat = 0
    private var accDY: CGFloat = 0
    private var running = false

    var rdpId: String? = nil   // nếu có → điều khiển qua cầu nối RDP máy chủ (máy thuê)

    init(api: APIClient, agentId: String, rdpId: String? = nil) {
        self.api = api; self.agentId = agentId; self.rdpId = rdpId
    }
    // StateObject không truy cập được store lúc init → gán lại máy chủ + token thật khi onAppear.
    func rebind(api: APIClient) { self.api = api }

    func start() {
        guard !running else { return }
        running = true
        Task { await moveLoop() }
        Task { await screenLoop() }
    }
    func stop() { running = false }

    // Gộp delta rồi gửi mỗi 45ms → con trỏ mượt, không giật, không dồn hàng.
    func addDelta(_ dx: CGFloat, _ dy: CGFloat) {
        accDX += dx * CGFloat(speed)
        accDY += dy * CGFloat(speed)
    }

    private func moveLoop() async {
        while running {
            if abs(accDX) >= 1 || abs(accDY) >= 1 {
                let dx = Int(accDX.rounded()), dy = Int(accDY.rounded())
                accDX = 0; accDY = 0
                send(["t": "move", "dx": dx, "dy": dy])
            }
            try? await Task.sleep(nanoseconds: 45_000_000)
        }
    }

    private func screenLoop() async {
        while running {
            if let rid = rdpId {
                if let s = try? await api.rdpScreen(rid) {
                    online = s.running
                    if !s.jpg.isEmpty, let data = Data(base64Encoded: s.jpg), let img = UIImage(data: data) {
                        screen = img
                    }
                }
            } else if let s = try? await api.pcScreen(agentId: agentId) {
                online = s.online
                if !s.jpg.isEmpty, let data = Data(base64Encoded: s.jpg), let img = UIImage(data: data) {
                    screen = img
                }
            }
            // Nhận khung ~7 fps cho khớp agent/bridge (mượt hơn nhiều so với 0.6s cũ).
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    func send(_ cmd: [String: Any]) {
        if let rid = rdpId {
            Task { try? await api.rdpInput(rid, cmd: cmd) }
        } else {
            Task { try? await api.pcSend(agentId: agentId, cmd: cmd) }
        }
    }
    func click(_ b: String) { send(["t": "click", "b": b]) }
    func scroll(_ dy: Int) { send(["t": "scroll", "dy": dy]) }
    func key(_ k: String) { send(["t": "key", "k": k]) }
    func text(_ s: String) { send(["t": "text", "s": s]) }
    func media(_ a: String) { send(["t": "media", "a": a]) }
    func sys(_ a: String) { send(["t": "sys", "a": a]) }
}

// MARK: - Màn điều khiển (trackpad + phím) — như PC Controller

struct PCControllerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let agent: PCAgent
    var apiOverride: APIClient? = nil   // token tài khoản đã lưu (nil = tài khoản hiện tại)
    var rdpId: String? = nil            // nếu có → điều khiển máy thuê qua cầu nối RDP

    @StateObject private var eng: PCEngine
    @State private var lastTrans: CGSize?
    @State private var kbText = ""
    @FocusState private var kbFocused: Bool
    @State private var fullscreen = false

    init(agent: PCAgent, apiOverride: APIClient? = nil, rdpId: String? = nil) {
        self.agent = agent
        self.apiOverride = apiOverride
        self.rdpId = rdpId
        // api dựng tạm; sẽ được cấp lại trong onAppear.
        _eng = StateObject(wrappedValue: PCEngine(api: APIClient(baseURL: "", token: nil),
                                                  agentId: agent.agentId, rdpId: rdpId))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 10) {
                header
                screenPreview
                trackpad
                speedBar
                clickButtons
                controlGrid
                Text(store.t("Kết nối qua KENIOS · Zoom & Toàn màn hình",
                             "Connected via KENIOS · Zoom & Fullscreen"))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            // Ô nhập ẩn cho bàn phím
            TextField("", text: $kbText)
                .focused($kbFocused)
                .opacity(0.01).frame(width: 1, height: 1)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onChange(of: kbText) { v in
                    guard !v.isEmpty else { return }
                    eng.text(v); kbText = ""
                }
        }
        .onAppear {
            eng.rebind(api: apiOverride ?? store.api)   // token tài khoản đã lưu, hoặc tài khoản hiện tại
            eng.start()
        }
        .onDisappear {
            eng.stop()
            if let rid = rdpId {   // đóng phiên RDP ở máy chủ để giải phóng tài nguyên
                let api = apiOverride ?? store.api
                Task { try? await api.rdpStop(rid) }
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            PCFullscreen(eng: eng, lastTrans: $lastTrans) { fullscreen = false }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3.bold()) }
            Spacer()
            Text("PC CONTROLLER").font(.headline.bold()).foregroundStyle(Theme.accent).tracking(2)
            Spacer()
            Circle().fill(eng.online ? .green : .orange).frame(width: 10, height: 10)
        }.padding(.top, 8)
    }

    private var screenPreview: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let img = eng.screen {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    ZStack { Color.black; ProgressView().tint(.white) }
                }
            }
            .frame(height: 150).frame(maxWidth: .infinity)
            .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12))

            Button { fullscreen = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body).foregroundStyle(.white).padding(8)
                    .background(.black.opacity(0.5)).clipShape(Circle())
            }.padding(8)
        }
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
            .overlay(
                Text(store.t("VUỐT ĐỂ DI CHUỘT · CHẠM = CLICK", "SWIPE TO MOVE · TAP = CLICK"))
                    .font(.caption2.bold()).foregroundStyle(.tertiary)
            )
            .frame(height: 150)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if let last = lastTrans {
                            eng.addDelta(v.translation.width - last.width, v.translation.height - last.height)
                        }
                        lastTrans = v.translation
                    }
                    .onEnded { v in
                        if hypot(v.translation.width, v.translation.height) < 8 { eng.click("left") }
                        lastTrans = nil
                    }
            )
    }

    private var speedBar: some View {
        HStack(spacing: 10) {
            Text(store.t("Tốc độ", "Speed")).font(.caption).foregroundStyle(.secondary)
            Slider(value: $eng.speed, in: 1...6, step: 0.5)
            Text(String(format: "%.1fx", eng.speed)).font(.caption.bold()).foregroundStyle(Theme.accent)
                .frame(width: 42)
        }
    }

    private var clickButtons: some View {
        HStack(spacing: 10) {
            padButton(store.t("◁ Chuột trái", "◁ Left Click")) { eng.click("left") }
            padButton(store.t("Chuột phải ▷", "Right Click ▷")) { eng.click("right") }
        }
    }

    private var controlGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 8) {
            gridBtn("backward.end.fill", "Prev") { eng.media("prev") }
            gridBtn("playpause.fill", "Play") { eng.media("playpause") }
            gridBtn("forward.end.fill", "Next") { eng.media("next") }
            gridBtn("speaker.slash.fill", "Mute") { eng.media("mute") }
            gridBtn("speaker.wave.1.fill", "Vol -") { eng.media("voldown") }
            gridBtn("speaker.wave.3.fill", "Vol +") { eng.media("volup") }
            gridBtn("menubar.dock.rectangle", "Desktop") { eng.sys("desktop") }
            gridBtn("lock.fill", "Lock PC") { eng.sys("lock") }
            gridBtn("keyboard", "Keyboard") { kbFocused = true }
            gridBtn("delete.left.fill", "Backspace") { eng.key("backspace") }
            gridBtn("space", "Space") { eng.key("space") }
            gridBtn("return", "Enter") { eng.key("enter") }
            gridBtn("chevron.up", store.t("Cuộn lên", "Scroll ↑")) { eng.scroll(-3) }
            gridBtn("chevron.down", store.t("Cuộn xuống", "Scroll ↓")) { eng.scroll(3) }
            gridBtn("cursorarrow.click.2", "Double") { eng.click("double") }
            gridBtn("arrow.up.left.and.arrow.down.right", store.t("Toàn màn", "Fullscreen")) { fullscreen = true }
        }
    }

    private func padButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 46)
                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func gridBtn(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.body).foregroundStyle(Theme.purple)
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).frame(height: 58)
            .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

// MARK: - Toàn màn hình (xem lớn + vẫn điều khiển được)

struct PCFullscreen: View {
    @ObservedObject var eng: PCEngine
    @Binding var lastTrans: CGSize?
    var onClose: () -> Void
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = eng.screen {
                Image(uiImage: img).resizable().scaledToFit().scaleEffect(zoom)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            // Lớp điều khiển: vuốt = di chuột, chạm = click
            Color.clear.contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if let last = lastTrans {
                                eng.addDelta(v.translation.width - last.width, v.translation.height - last.height)
                            }
                            lastTrans = v.translation
                        }
                        .onEnded { v in
                            if hypot(v.translation.width, v.translation.height) < 8 { eng.click("left") }
                            lastTrans = nil
                        }
                )
                .simultaneousGesture(MagnificationGesture().onChanged { zoom = max(1, min(4, $0)) })
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Button { eng.click("left") } label: { Text("Click").font(.caption.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.5)).clipShape(Capsule()) }
                    Button { eng.click("right") } label: { Text("R-Click").font(.caption.bold()).foregroundStyle(.white).padding(8).background(.black.opacity(0.5)).clipShape(Capsule()) }
                }
                .padding(.horizontal, 14).padding(.vertical, 8).background(.ultraThinMaterial)
                Spacer()
            }
        }
    }
}

// MARK: - Kiến trúc Windows App (tài liệu trực quan)

struct WinAppArchitectureDetail: View {
    @EnvironmentObject var store: AppStore
    private let cBlue = Color(red: 0.12, green: 0.53, blue: 0.90)
    private let cPurple = Color(red: 0.56, green: 0.14, blue: 0.67)
    private let cOrange = Color(red: 0.98, green: 0.55, blue: 0.0)
    private let cGreen = Color(red: 0.26, green: 0.63, blue: 0.28)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(store.t("Kiến trúc hệ thống", "System architecture")).font(.headline)
                layer(1, cBlue, "iphone", store.t("Thiết bị di động", "Client device"),
                      store.t("Giao diện chạm · trackpad · bàn phím ảo · ánh xạ phím media", "Touch UI · trackpad · virtual keyboard · media keys"))
                down
                layer(2, cPurple, "lock.shield.fill", store.t("Bảo mật & lệnh", "Security & commands"),
                      store.t("Đăng nhập tài khoản KENIOS (token) · lệnh chuột/phím mã hoá qua HTTPS", "KENIOS account login (token) · mouse/keyboard over HTTPS"))
                down
                layer(3, cOrange, "network", store.t("Cầu nối KENIOS (relay)", "KENIOS relay"),
                      store.t("Máy chủ trung chuyển lệnh + ảnh màn hình, kiểm tra chủ sở hữu (KHÔNG cần nhập VPS)", "Relays commands + frames, checks ownership (no VPS to type)"))
                down
                layer(4, cGreen, "pc", store.t("Agent trên PC", "PC agent"),
                      store.t("Thực thi chuột/phím/media, chụp màn hình đẩy về (Windows/macOS/Linux)", "Executes input, captures screen (Windows/macOS/Linux)"))

                Divider().padding(.vertical, 4)
                Text(store.t("Cơ chế hoạt động", "How it works")).font(.headline)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").font(.caption.bold()).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Theme.accent).clipShape(Circle())
                        Text(s).font(.caption); Spacer(minLength: 0)
                    }
                }
                Divider().padding(.vertical, 4)
                Text(store.t("Vì sao bản này không cần nhập VPS", "Why no VPS to enter")).font(.subheadline.bold())
                Text(store.t("App dùng luôn máy chủ KENIOS bạn đã đăng nhập làm cầu nối; agent trên PC cũng đăng nhập cùng tài khoản → hai bên tự tìm thấy nhau. Bạn chỉ cần chạy agent, không gõ IP/cổng. Muốn dùng trên trình duyệt: mở …/pc.",
                             "The app reuses your logged-in KENIOS server as the relay; the PC agent signs in with the same account → they find each other automatically. Just run the agent — no IP/port. For a browser, open …/pc."))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
        .navigationTitle(store.t("Kiến trúc", "Architecture"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var steps: [String] {
        [
            store.t("Chạy agent trên PC, đăng nhập tài khoản KENIOS → máy đăng ký lên máy chủ.",
                    "Run the agent on the PC, sign in with KENIOS → the PC registers on the server."),
            store.t("Mở app (Windows App) hoặc web …/pc → chọn máy đang online.",
                    "Open the app (Windows App) or web …/pc → pick the online PC."),
            store.t("Bạn vuốt/bấm → lệnh gửi lên máy chủ; agent hỏi lệnh (~60ms) và thực thi ngay.",
                    "You swipe/tap → commands go to the server; the agent polls (~60ms) and executes."),
            store.t("Agent chụp màn hình đẩy về để bạn xem preview thời gian thực.",
                    "The agent streams the screen back for a real-time preview."),
        ]
    }

    private func layer(_ n: Int, _ color: Color, _ icon: String, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("\(n)").font(.subheadline.bold()).foregroundStyle(color)
                    .frame(width: 26, height: 26).background(color.opacity(0.15)).clipShape(Circle())
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.subheadline.bold()); Spacer()
            }
            Text(desc).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.4), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private var down: some View {
        Image(systemName: "arrow.down").font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
}

// MARK: - Add PC (giao diện giống Microsoft Remote Desktop, kết nối qua agent KENIOS)
struct AddRemotePCView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var existing: SavedPC? = nil
    var onSave: (SavedPC) -> Void

    @State private var host = ""
    @State private var friendly = ""
    @State private var account = ""
    @State private var password = ""
    @State private var adminMode = false
    @State private var swapMouse = false
    @State private var showCreds = false

    init(existing: SavedPC? = nil, onSave: @escaping (SavedPC) -> Void) {
        self.existing = existing
        self.onSave = onSave
        _host = State(initialValue: existing?.host ?? "")
        _friendly = State(initialValue: existing?.friendlyName ?? "")
        _account = State(initialValue: existing?.account ?? "")
        _password = State(initialValue: existing?.password ?? "")
        _adminMode = State(initialValue: existing?.adminMode ?? false)
        _swapMouse = State(initialValue: existing?.swapMouse ?? false)
    }

    private var credsSummary: String {
        account.isEmpty ? store.t("Hỏi khi cần", "Ask When Required") : account
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(store.t("Tên PC", "PC Name"))
                        Spacer()
                        TextField(store.t("Hostname hoặc IP", "Hostname or IP"), text: $host)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Button { showCreds = true } label: {
                        HStack {
                            Text(store.t("Thông tin đăng nhập", "Credentials")).foregroundStyle(.primary)
                            Spacer()
                            Text(credsSummary).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Section(store.t("CHUNG", "GENERAL")) {
                    HStack {
                        Text(store.t("Tên gợi nhớ", "Friendly Name"))
                        Spacer()
                        TextField(store.t("Tuỳ chọn", "Optional"), text: $friendly)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle(store.t("Chế độ quản trị", "Admin Mode"), isOn: $adminMode)
                    Toggle(store.t("Đảo nút chuột", "Swap Mouse Buttons"), isOn: $swapMouse)
                }
                Section {
                    Text(store.t("Kết nối qua KENIOS: PC phải chạy pc-agent và đăng nhập đúng tài khoản ở trên. Không cần mở cổng/VPS.",
                                 "Connect via KENIOS: the PC must run pc-agent signed in with the account above. No port/VPS needed."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("Thêm PC", "Add PC"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Lưu", "Save")) { save() }.bold()
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty
                                  && friendly.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showCreds) {
                CredentialsEntryView(account: $account, password: $password).environmentObject(store)
            }
        }
    }

    private func save() {
        var pc = existing ?? SavedPC()
        pc.host = host.trimmingCharacters(in: .whitespaces)
        pc.friendlyName = friendly.trimmingCharacters(in: .whitespaces)
        pc.account = account.trimmingCharacters(in: .whitespaces)
        pc.password = password
        pc.adminMode = adminMode
        pc.swapMouse = swapMouse
        onSave(pc)
        dismiss()
    }
}

// Hộp "Nhập thông tin đăng nhập" (giống ảnh 2 — Enter Your Credentials)
struct CredentialsEntryView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var account: String
    @Binding var password: String
    @State private var a = ""
    @State private var p = ""

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("Nhập thông tin đăng nhập", "Enter Your Credentials")).font(.headline)
                Text(store.t("Thông tin này dùng để kết nối tới PC từ xa.",
                             "These credentials will be used to connect to a remote PC."))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                TextField(store.t("Tài khoản KENIOS", "KENIOS account"), text: $a)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textContentType(.username)
                    .padding(12)
                Divider()
                SecureField(store.t("Mật khẩu", "Password"), text: $p)
                    .textContentType(.password).padding(12)
            }
            .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(role: .cancel) { dismiss() } label: {
                    Text(store.t("Huỷ", "Cancel")).foregroundStyle(.red)
                        .frame(maxWidth: .infinity).padding()
                        .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                }
                Button {
                    account = a.trimmingCharacters(in: .whitespaces); password = p; dismiss()
                } label: {
                    Text(store.t("Tiếp tục", "Continue")).bold().foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding()
                        .background(Theme.accent).clipShape(Capsule())
                }
            }
            Spacer()
        }
        .padding()
        .onAppear { a = account; p = password }
        .presentationDetents([.height(300)])
    }
}

// §11b — Phiên RDP đang mở (dùng cho fullScreenCover)
struct RDPOpen: Identifiable {
    let id = UUID()
    let rid: String
    let host: String
    let w: Int
    let h: Int
}

// Form kết nối máy thuê bằng IP + tài khoản + mật khẩu (máy chủ KENIOS làm cầu nối RDP)
struct RDPConnectView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onConnected: (RDPOpen) -> Void

    @State private var host = ""
    @State private var user = ""
    @State private var pass = ""
    @State private var connecting = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Thông tin máy thuê", "Rented PC details")) {
                    TextField(store.t("IP hoặc Hostname (vd 103.20.1.5)", "IP or Hostname (e.g. 103.20.1.5)"), text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField(store.t("Tài khoản (vd Administrator)", "Account (e.g. Administrator)"), text: $user)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(store.t("Mật khẩu", "Password"), text: $pass)
                }
                if let err { Section { Text(err).foregroundStyle(.red).font(.caption) } }
                Section {
                    Button { connect() } label: {
                        HStack {
                            if connecting { ProgressView().padding(.trailing, 4) }
                            Text(connecting ? store.t("Đang kết nối… (có thể mất vài giây)", "Connecting… (may take a few seconds)")
                                            : store.t("Kết nối", "Connect")).bold()
                            Spacer()
                        }
                    }
                    .disabled(connecting || host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Section {
                    Text(store.t("Máy chủ KENIOS sẽ mở kết nối RDP tới máy này giúp bạn — KHÔNG cần cài gì lên máy thuê. Máy cần có IP công khai và đã bật Remote Desktop (cổng 3389).",
                                 "The KENIOS server opens the RDP connection to this PC for you — nothing to install on the rented PC. It needs a public IP with Remote Desktop enabled (port 3389)."))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.t("Kết nối bằng IP", "Connect by IP"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
        }
    }

    private func connect() {
        connecting = true; err = nil
        Task {
            defer { connecting = false }
            do {
                let r = try await store.api.rdpStart(
                    host: host.trimmingCharacters(in: .whitespaces),
                    username: user.trimmingCharacters(in: .whitespaces),
                    password: pass)
                onConnected(RDPOpen(rid: r.rdpId, host: host.trimmingCharacters(in: .whitespaces), w: r.w, h: r.h))
            } catch {
                let raw = error.localizedDescription
                if raw.lowercased().contains("chưa cài") || raw.contains("503") {
                    err = store.t("Máy chủ KENIOS chưa cài công cụ RDP. Chạy lại capnhat-vps.sh trên VPS rồi thử lại.\n(",
                                  "The KENIOS server hasn't installed RDP tools yet. Re-run capnhat-vps.sh on the VPS.\n(") + raw + ")"
                } else {
                    err = store.t("Kết nối thất bại: ", "Connection failed: ") + raw
                }
            }
        }
    }
}
