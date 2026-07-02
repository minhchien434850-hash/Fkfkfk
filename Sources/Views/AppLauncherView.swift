import SwiftUI

// ======================== App Launcher — app do bạn tự thêm ========================
// Thêm app từ màn hình chính của bạn (qua URL scheme) → dọn RAM → mở app nhanh.

struct AppLauncherView: View {
    @EnvironmentObject var store: AppStore
    private let launcher = AppLauncher.shared

    @State private var apps: [CustomApp] = []
    @State private var memInfo = AppLauncher.MemoryInfo(used: 0, total: 0)
    @State private var thermalText = ("Bình thường", "checkmark.seal.fill")
    @State private var cleaning = false
    @State private var cleanDone = false
    @State private var timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    // Thêm / sửa app
    @State private var editingApp: CustomApp?       // nil = đang thêm mới
    @State private var showForm = false
    // Báo lỗi khi mở app thất bại
    @State private var failedApp: CustomApp?

    // Bảng màu gradient cho icon app
    static let palette: [[Color]] = [
        [Color(red: 0.9, green: 0.2, blue: 0.3), Color(red: 0.7, green: 0.1, blue: 0.2)],
        [Color(red: 1.0, green: 0.5, blue: 0.0), Color(red: 0.9, green: 0.3, blue: 0.0)],
        [Color(red: 0.2, green: 0.5, blue: 0.9), Color(red: 0.1, green: 0.3, blue: 0.7)],
        [Color(red: 0.0, green: 0.8, blue: 0.5), Color(red: 0.0, green: 0.6, blue: 0.4)],
        [Color(red: 0.6, green: 0.3, blue: 0.9), Color(red: 0.4, green: 0.2, blue: 0.7)],
        [Color(red: 0.95, green: 0.75, blue: 0.1), Color(red: 0.85, green: 0.55, blue: 0.0)],
        [Color(red: 0.15, green: 0.65, blue: 0.65), Color(red: 0.05, green: 0.45, blue: 0.55)],
        [Color(red: 0.95, green: 0.35, blue: 0.6), Color(red: 0.75, green: 0.2, blue: 0.5)],
    ]
    static func colors(_ index: Int) -> [Color] {
        palette[((index % palette.count) + palette.count) % palette.count]
    }

    private let cols = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    systemStatusCard
                    optimizeButton
                    appGrid
                    if apps.isEmpty { emptyGuide }
                }
                .padding()
            }
            .background(Theme.bgNavy.ignoresSafeArea())
            .navigationTitle(store.t("App Launcher", "App Launcher"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingApp = nil
                        showForm = true
                    } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .onAppear { apps = launcher.loadApps(); refreshStatus() }
            .onReceive(timer) { _ in refreshStatus() }
            .sheet(isPresented: $showForm) {
                AppFormView(app: editingApp) { saved in
                    if editingApp == nil { launcher.addApp(saved) }
                    else { launcher.updateApp(saved) }
                    apps = launcher.loadApps()
                }
                .environmentObject(store)
            }
            .alert(store.t("Không mở được app", "Could not open app"),
                   isPresented: Binding(get: { failedApp != nil }, set: { if !$0 { failedApp = nil } })) {
                if let app = failedApp, app.appStoreURL != nil {
                    Button(store.t("Mở App Store", "Open App Store")) {
                        launcher.openAppStore(app)
                        failedApp = nil
                    }
                }
                Button(store.t("Đóng", "Close"), role: .cancel) { failedApp = nil }
            } message: {
                Text(store.t("App chưa cài trên máy hoặc URL scheme chưa đúng. Kiểm tra lại scheme trong phần sửa app.",
                             "The app is not installed or the URL scheme is wrong. Check the scheme in the app editor."))
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        KHeroHeader(
            icon: "bolt.heart.fill",
            title: store.t("App Launcher", "App Launcher"),
            subtitle: store.t("Thêm app của bạn · Dọn RAM · Mở nhanh", "Add your apps · Clean RAM · Launch fast")
        )
    }

    // MARK: - System Status Card

    private var systemStatusCard: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: "cpu")
                    .font(.headline)
                    .foregroundStyle(Theme.gold)
                Text(store.t("Trạng thái hệ thống", "System Status"))
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
            }

            HStack(spacing: 16) {
                // RAM
                statusPill(
                    icon: "memorychip",
                    label: "RAM",
                    value: "\(memInfo.freeMB) MB " + store.t("trống", "free"),
                    color: memInfo.usagePercent < 60 ? .green : memInfo.usagePercent < 80 ? .orange : .red
                )

                // Nhiệt độ
                statusPill(
                    icon: thermalText.1,
                    label: store.t("Nhiệt", "Thermal"),
                    value: store.t(thermalText.0, thermalText.0),
                    color: thermalColor
                )
            }

            // RAM bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(store.t("Bộ nhớ App:", "App memory:"))
                        .font(.caption2).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(memInfo.usedMB) / \(memInfo.totalMB) MB")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(ramBarColor)
                            .frame(width: geo.size.width * min(memInfo.usagePercent / 100, 1.0))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Optimize Button

    private var optimizeButton: some View {
        Button {
            runCleanup()
        } label: {
            HStack(spacing: 12) {
                if cleaning {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: cleanDone ? "checkmark.circle.fill" : "bolt.fill")
                        .font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cleaning
                         ? store.t("Đang tối ưu...", "Optimizing...")
                         : cleanDone
                           ? store.t("Đã tối ưu xong!", "Optimization complete!")
                           : store.t("Tối ưu hiệu năng", "Optimize Performance"))
                        .font(.headline.bold())
                    if !cleaning && !cleanDone {
                        Text(store.t("Dọn RAM · Xoá cache · Giải phóng tài nguyên",
                                     "Clean RAM · Clear cache · Free resources"))
                            .font(.caption2)
                            .opacity(0.8)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                cleanDone
                    ? LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    : LinearGradient(colors: [Color(red: 1, green: 0.4, blue: 0), Color(red: 1, green: 0.6, blue: 0.1)], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: (cleanDone ? Color.green : Color.orange).opacity(0.4), radius: 10, y: 4)
        }
        .disabled(cleaning)
    }

    // MARK: - App Grid

    private var appGrid: some View {
        LazyVGrid(columns: cols, spacing: 14) {
            ForEach(apps) { app in
                appCard(app)
            }
            addCard
        }
    }

    private func appCard(_ app: CustomApp) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: Self.colors(app.colorIndex),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)
                    .shadow(color: Self.colors(app.colorIndex).first!.opacity(0.4), radius: 8, y: 4)

                Image(systemName: app.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text(app.name)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)

            Button {
                launcher.optimizeAndLaunch(app) { ok in
                    if !ok { failedApp = app }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(store.t("Tối ưu & Mở", "Optimize & Open"))
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            Button {
                editingApp = app
                showForm = true
            } label: {
                Label(store.t("Sửa app", "Edit app"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                launcher.deleteApp(app)
                apps = launcher.loadApps()
            } label: {
                Label(store.t("Xoá app", "Delete app"), systemImage: "trash")
            }
        }
    }

    // Ô "+" thêm app mới ngay trong lưới
    private var addCard: some View {
        Button {
            editingApp = nil
            showForm = true
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: 62, height: 62)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                Text(store.t("Thêm app", "Add app"))
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.accent)
                    .frame(height: 30)
                Text(store.t("của bạn", "your own"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // Hướng dẫn khi chưa có app nào
    private var emptyGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.t("💡 Cách thêm app của bạn:", "💡 How to add your apps:")).font(.footnote).bold()
                .foregroundStyle(.white)
            Group {
                Text(store.t("• Bấm nút ＋ ở trên hoặc ô 'Thêm app' trong lưới.",
                             "• Tap ＋ above or the 'Add app' tile."))
                Text(store.t("• Nhập tên app và URL scheme (vd: youtube, fb, zalo, tiktok, instagram, shopee...).",
                             "• Enter the app name and URL scheme (e.g. youtube, fb, zalo, tiktok, instagram, shopee...)."))
                Text(store.t("• Giữ tay lên app đã thêm để Sửa hoặc Xoá.",
                             "• Long-press an added app to Edit or Delete."))
                Text(store.t("• Khi bấm 'Tối ưu & Mở', KENIOS dọn RAM rồi chuyển thẳng sang app đó.",
                             "• 'Optimize & Open' cleans RAM then switches to that app."))
            }
            .font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Helpers

    private func refreshStatus() {
        memInfo = launcher.memoryInfo()
        thermalText = launcher.thermalStateText()
    }

    private func runCleanup() {
        cleaning = true
        cleanDone = false
        launcher.cleanupBeforeLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            cleaning = false
            cleanDone = true
            refreshStatus()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                cleanDone = false
            }
        }
    }

    private var thermalColor: Color {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return .green
        case .fair:     return .yellow
        case .serious:  return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }

    private var ramBarColor: LinearGradient {
        let pct = memInfo.usagePercent
        if pct < 60 {
            return LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
        } else if pct < 80 {
            return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing)
        } else {
            return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func statusPill(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ======================== Form thêm / sửa app ========================

struct AppFormView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let onSave: (CustomApp) -> Void

    @State private var app: CustomApp
    @State private var search = ""
    private let isEditing: Bool

    init(app: CustomApp?, onSave: @escaping (CustomApp) -> Void) {
        self.onSave = onSave
        self.isEditing = app != nil
        _app = State(initialValue: app ?? CustomApp(name: "", urlScheme: ""))
    }

    private var canSave: Bool {
        !app.name.trimmingCharacters(in: .whitespaces).isEmpty && app.schemeURL != nil
    }

    private let iconCols = [GridItem(.adaptive(minimum: 44), spacing: 10)]
    private let pickCols = [GridItem(.flexible()), GridItem(.flexible()),
                            GridItem(.flexible()), GridItem(.flexible())]

    private var filteredPresets: [CustomApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return AppLauncher.presets }
        return AppLauncher.presets.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    // Thêm ngay 1 app từ danh mục (cấp id mới để không trùng khi thêm nhiều app)
    private func addPreset(_ preset: CustomApp) {
        var p = preset
        p.id = UUID()
        onSave(p)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField(store.t("Tìm app theo tên (vd: YouTube)...", "Search app by name..."), text: $search)
                                .autocorrectionDisabled()
                        }
                        let items = filteredPresets
                        if items.isEmpty {
                            Text(store.t("Không thấy app này — anh tự nhập bên dưới nhé.",
                                         "App not found — enter it manually below."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: pickCols, spacing: 12) {
                                ForEach(items) { p in
                                    Button { addPreset(p) } label: {
                                        VStack(spacing: 6) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .fill(LinearGradient(colors: AppLauncherView.colors(p.colorIndex),
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    .frame(width: 54, height: 54)
                                                Image(systemName: p.icon).font(.title3.weight(.semibold)).foregroundStyle(.white)
                                            }
                                            Text(p.name).font(.caption2).lineLimit(1).foregroundStyle(.primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(store.t("Chọn nhanh — bấm 1 phát là thêm", "Quick pick — one tap to add"))
                    } footer: {
                        Text(store.t("Gõ tên để tìm, bấm là thêm ngay (khỏi cần URL). Không thấy thì tự nhập bên dưới.",
                                     "Type to search, tap to add instantly (no URL needed). Not listed? Enter it below."))
                            .font(.caption2)
                    }
                }

                Section(store.t("Thông tin app", "App info")) {
                    TextField(store.t("Tên app (vd: YouTube)", "App name (e.g. YouTube)"), text: $app.name)
                    TextField("URL scheme (vd: youtube, fb, zalo...)", text: $app.urlScheme)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField(store.t("App Store ID (tuỳ chọn, chỉ số)", "App Store ID (optional, digits)"), text: $app.appStoreID)
                        .keyboardType(.numberPad)
                }

                Section(store.t("Biểu tượng", "Icon")) {
                    LazyVGrid(columns: iconCols, spacing: 10) {
                        ForEach(AppLauncher.iconChoices, id: \.self) { ic in
                            Button {
                                app.icon = ic
                            } label: {
                                Image(systemName: ic)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(app.icon == ic ? Theme.accent.opacity(0.2) : Color(.tertiarySystemBackground))
                                    .foregroundStyle(app.icon == ic ? Theme.accent : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(app.icon == ic ? Theme.accent : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(store.t("Màu icon", "Icon color")) {
                    HStack(spacing: 12) {
                        ForEach(0..<AppLauncherView.palette.count, id: \.self) { i in
                            Button {
                                app.colorIndex = i
                            } label: {
                                Circle()
                                    .fill(LinearGradient(colors: AppLauncherView.colors(i),
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle().stroke(app.colorIndex == i ? Color.primary : .clear, lineWidth: 2.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                Section {
                    // Xem trước
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: AppLauncherView.colors(app.colorIndex),
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 50, height: 50)
                            Image(systemName: app.icon)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name.isEmpty ? store.t("Tên app", "App name") : app.name)
                                .font(.subheadline.bold())
                            Text(app.schemeURL?.absoluteString ?? "scheme://")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(store.t("Xem trước", "Preview"))
                }

                Section(store.t("Cách tìm URL scheme", "How to find URL schemes")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t("Một số scheme phổ biến: youtube · fb · zalo · tiktok · instagram · shopee · momo · grab · telegram · whatsapp",
                                     "Common schemes: youtube · fb · zalo · tiktok · instagram · shopee · momo · grab · telegram · whatsapp"))
                        Text(store.t("Tìm Google: \"tên app + URL scheme iOS\" để biết scheme của app khác.",
                                     "Google: \"app name + iOS URL scheme\" to find other apps' schemes."))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? store.t("Sửa app", "Edit app") : store.t("Thêm app", "Add app"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(store.t("Huỷ", "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.t("Lưu", "Save")) {
                        app.name = app.name.trimmingCharacters(in: .whitespaces)
                        app.urlScheme = app.urlScheme.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(app)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
