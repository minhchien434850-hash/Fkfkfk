import SwiftUI

// §11c — "Remote Desktop": bảng điều khiển đẹp gộp mọi cách kết nối PC vào 1 chỗ.
//  • Máy chạy agent (hiện online) — thẻ lớn, bấm là điều khiển.
//  • Kết nối nhanh máy thuê bằng IP + tài khoản (cầu nối RDP máy chủ).
//  • Kết nối đã lưu (Add PC) — đăng nhập bằng tài khoản.
//  Dùng lại engine/màn điều khiển KENIOS-native (PCControllerView) — CHẠY THẬT.
struct RemoteDesktopHubView: View {
    @EnvironmentObject var store: AppStore
    @State private var pcs: [PCAgent] = []
    @State private var saved: [SavedPC] = SavedPCStore.load()
    @State private var loading = true

    @State private var openPC: PCAgent?
    @State private var openAPI: APIClient?
    @State private var rdpOpen: RDPOpen?
    @State private var showRDP = false
    @State private var showAddPC = false
    @State private var editingPC: SavedPC?
    @State private var connecting = false
    @State private var msg: String?

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    quickConnect
                    devicesSection
                    savedSection
                    tipRow
                }
                .padding()
            }
            .navigationTitle("Remote Desktop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .task { await reload() }
            .refreshable { await reload() }
            .fullScreenCover(item: $openPC) { p in
                PCControllerView(agent: p, apiOverride: openAPI).environmentObject(store)
            }
            .fullScreenCover(item: $rdpOpen) { o in
                PCControllerView(agent: PCAgent(agentId: o.rid, name: o.host, os: "Windows", online: true),
                                 rdpId: o.rid).environmentObject(store)
            }
            .sheet(isPresented: $showRDP) {
                RDPConnectView { open in
                    showRDP = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { rdpOpen = open }
                }.environmentObject(store)
            }
            .sheet(isPresented: $showAddPC) {
                AddRemotePCView { pc in saved.append(pc); SavedPCStore.save(saved) }.environmentObject(store)
            }
            .sheet(item: $editingPC) { pc in
                AddRemotePCView(existing: pc) { up in
                    if let i = saved.firstIndex(where: { $0.id == up.id }) { saved[i] = up; SavedPCStore.save(saved) }
                }.environmentObject(store)
            }
        }
    }

    // Hero gradient
    private var hero: some View {
        HStack(spacing: 14) {
            Image(systemName: "display")
                .font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .background(.white.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text("Remote Desktop").font(.title2.bold()).foregroundStyle(.white)
                Text(store.t("Điều khiển mọi máy tính — agent, máy thuê (IP), đã lưu",
                             "Control any computer — agent, rented (IP), saved"))
                    .font(.caption).foregroundStyle(.white.opacity(0.9))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(LinearGradient(colors: [Color(red: 0.0, green: 0.47, blue: 0.84),
                                            Color(red: 0.35, green: 0.15, blue: 0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // Kết nối nhanh: máy thuê (IP) + thêm PC
    private var quickConnect: some View {
        HStack(spacing: 12) {
            bigAction(icon: "network", title: store.t("Máy thuê (IP)", "Rented (IP)"),
                      sub: store.t("IP · user · pass", "IP · user · pass"), color: .blue) { showRDP = true }
            bigAction(icon: "plus.rectangle.on.rectangle", title: store.t("Thêm PC", "Add PC"),
                      sub: store.t("Lưu bằng tài khoản", "Save by account"), color: .purple) { showAddPC = true }
        }
    }

    private func bigAction(icon: String, title: String, sub: String, color: Color, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2.bold()).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(color).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(title).font(.subheadline.bold()).foregroundStyle(.primary)
                Text(sub).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).kCard(16)
        }.buttonStyle(.plain)
    }

    // Thiết bị đang chạy agent
    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(store.t("Thiết bị của bạn", "Your devices"), systemImage: "pc").font(.headline)
                Spacer()
                if loading { ProgressView() }
            }
            if let msg { Text(msg).font(.caption).foregroundStyle(.red) }
            if pcs.isEmpty && !loading {
                Text(store.t("Chưa có máy chạy agent. Dùng \"Máy thuê (IP)\" ở trên, hoặc chạy pc-agent trên PC.",
                             "No agent devices. Use \"Rented (IP)\" above, or run pc-agent on a PC."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(pcs) { p in deviceTile(p) }
                }
            }
        }
    }

    private func deviceTile(_ p: PCAgent) -> some View {
        Button {
            if p.online { openAPI = nil; openPC = p }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: p.os == "Darwin" ? "laptopcomputer" : "pc")
                        .font(.title2).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(p.online ? Theme.accent : Color.gray).clipShape(RoundedRectangle(cornerRadius: 12))
                    Spacer()
                    Circle().fill(p.online ? .green : .orange).frame(width: 10, height: 10)
                }
                Text(p.name).font(.subheadline.bold()).lineLimit(1).foregroundStyle(.primary)
                Text(p.online ? store.t("Đang online — bấm để điều khiển", "Online — tap to control")
                              : store.t("Ngoại tuyến", "Offline"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).kCard(16)
            .opacity(p.online ? 1 : 0.6)
        }.buttonStyle(.plain).disabled(!p.online)
    }

    // Kết nối đã lưu (Add PC)
    @ViewBuilder private var savedSection: some View {
        if !saved.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(store.t("Đã lưu", "Saved"), systemImage: "bookmark.fill").font(.headline)
                if connecting { HStack { ProgressView(); Text(store.t("Đang kết nối…", "Connecting…")).font(.caption) } }
                ForEach(saved) { s in
                    Button { connectSaved(s) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").font(.title3).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(Theme.purple).clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(.subheadline.bold()).foregroundStyle(.primary)
                                Text(s.account.isEmpty ? store.t("Tài khoản hiện tại", "Current account") : s.account)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(12).kCard(14)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { editingPC = s } label: { Label(store.t("Sửa", "Edit"), systemImage: "pencil") }
                        Button(role: .destructive) {
                            saved.removeAll { $0.id == s.id }; SavedPCStore.save(saved)
                        } label: { Label(store.t("Xoá", "Delete"), systemImage: "trash") }
                    }
                }
            }
        }
    }

    private var tipRow: some View {
        Text(store.t("Mẹo: máy thuê chỉ cần IP + tài khoản + mật khẩu (máy chủ KENIOS làm cầu nối RDP). Máy của bạn thì chạy pc-agent để hiện ở \"Thiết bị của bạn\".",
                     "Tip: rented PCs only need IP + account + password (the KENIOS server bridges RDP). Your own PCs run pc-agent to appear under \"Your devices\"."))
            .font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding().kCard(14)
    }

    // MARK: - Actions
    private func reload() async {
        loading = true; defer { loading = false }
        saved = SavedPCStore.load()
        pcs = (try? await store.api.pcMine()) ?? []
    }

    private func connectSaved(_ s: SavedPC) {
        connecting = true; msg = nil
        Task {
            defer { connecting = false }
            do {
                let api: APIClient
                if s.account.isEmpty {
                    api = store.api
                } else {
                    let auth = try await store.api.login(s.account, s.password)
                    api = APIClient(baseURL: store.baseURL, token: auth.token)
                }
                let online = ((try? await api.pcMine()) ?? []).filter { $0.online }
                let target = online.first(where: { $0.name.caseInsensitiveCompare(s.host) == .orderedSame }) ?? online.first
                guard let agent = target else {
                    msg = store.t("Chưa thấy máy online cho tài khoản này. Hãy chạy pc-agent trên PC bằng đúng tài khoản.",
                                  "No online PC for this account. Run pc-agent on the PC with this account.")
                    return
                }
                openAPI = s.account.isEmpty ? nil : api
                openPC = agent
            } catch {
                msg = store.t("Đăng nhập thất bại: ", "Login failed: ") + error.localizedDescription
            }
        }
    }
}
