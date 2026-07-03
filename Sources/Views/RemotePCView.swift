import SwiftUI
import UIKit

// ============================================================================
//  §11 — Windows App / Điều khiển PC từ xa (relay qua KENIOS)
//  Không cần nhập VPS: app dùng luôn máy chủ KENIOS. Chạy agent (pc-agent) trên
//  PC, đăng nhập cùng tài khoản → máy tự hiện ở đây để điều khiển. Có cả bản Web.
// ============================================================================

struct RemotePCView: View {
    @EnvironmentObject var store: AppStore
    @State private var pcs: [PCAgent] = []
    @State private var loading = true
    @State private var openPC: PCAgent?

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
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .fullScreenCover(item: $openPC) { p in
                PCControllerView(agent: p).environmentObject(store)
            }
            .task { await reload() }
        }
    }

    private func reload() async {
        loading = true; defer { loading = false }
        pcs = (try? await store.api.pcMine()) ?? []
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

    init(api: APIClient, agentId: String) { self.api = api; self.agentId = agentId }
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
            if let s = try? await api.pcScreen(agentId: agentId) {
                online = s.online
                if !s.jpg.isEmpty, let data = Data(base64Encoded: s.jpg), let img = UIImage(data: data) {
                    screen = img
                }
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    func send(_ cmd: [String: Any]) {
        Task { try? await api.pcSend(agentId: agentId, cmd: cmd) }
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

    @StateObject private var eng: PCEngine
    @State private var lastTrans: CGSize?
    @State private var kbText = ""
    @FocusState private var kbFocused: Bool
    @State private var fullscreen = false

    init(agent: PCAgent) {
        self.agent = agent
        // api dựng tạm; sẽ được cấp lại từ store trong onAppear nếu cần
        _eng = StateObject(wrappedValue: PCEngine(api: APIClient(baseURL: "", token: nil), agentId: agent.agentId))
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
            eng.rebind(api: store.api)   // dùng đúng máy chủ + token đã đăng nhập
            eng.start()
        }
        .onDisappear { eng.stop() }
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
