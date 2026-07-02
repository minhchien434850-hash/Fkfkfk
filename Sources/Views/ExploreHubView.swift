import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation

// ======================== Khám phá — lưới nút đẹp, gom các tính năng phụ ========================
enum HubDest: String, Identifiable {
    case liveNow, fileTools, library, read, fun, games, appLauncher, tools, github, settings, admin, mediaConverter, messenger, remoteServer, remoteDesktop, certImport, ipaLibrary, myStore, pcRemote, remotePC
    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveNow:        return "Live Now"
        case .fileTools:      return "Công cụ tệp"
        case .library:        return "Thư viện"
        case .read:           return "Đọc (TTS)"
        case .fun:            return "Giải trí"
        case .games:          return "Trò chơi"
        case .appLauncher:    return "App Launcher"
        case .tools:          return "Công cụ"
        case .github:         return "GitHub"
        case .settings:       return "Cài đặt"
        case .admin:          return "Quản trị"
        case .mediaConverter: return "Chuyển đổi"
        case .messenger:      return "Nhắn tin"
        case .remoteServer:   return "Remote Server"
        case .remoteDesktop:  return "Điều khiển PC từ xa"
        case .certImport:     return "Chứng chỉ ký"
        case .ipaLibrary:     return "Kho IPA"
        case .myStore:        return "Cửa hàng của tôi"
        case .pcRemote:       return "PC Remote"
        case .remotePC:       return "Remote PC (Cloud)"
        }
    }
    var subtitle: String {
        switch self {
        case .liveNow:        return "Phát trực tiếp · TikTok · FB · YouTube"
        case .fileTools:      return "PDF · Âm thanh · Quét · Ảnh"
        case .library:        return "Video · file đã tải"
        case .read:           return "Đọc văn bản · giọng mới"
        case .fun:            return "Phim · nhạc · web"
        case .games:          return "Chơi game trong app"
        case .appLauncher:    return "Thêm app của bạn · Mở nhanh"
        case .tools:          return "Ảnh · tin tức · tiện ích"
        case .github:         return "Tải/xoá file lên repo"
        case .settings:       return "Tài khoản · giao diện"
        case .admin:          return "Quản lý người dùng"
        case .mediaConverter: return "Ảnh/Video → GIF · PNG"
        case .messenger:      return "Thủ công · Tự động Web"
        case .remoteServer:   return "SSH · SFTP · Chạy script VPS"
        case .remoteDesktop:  return "Xem & điều khiển màn hình PC"
        case .certImport:     return "Nhập .p12 · .mobileprovision"
        case .ipaLibrary:     return "Gom IPA · Ký & cài qua ESign"
        case .myStore:        return "Mở shop riêng · bán hàng"
        case .pcRemote:       return "Trackpad · Phím · Xem màn hình"
        case .remotePC:       return "IP+Pass · điều khiển qua VPS"
        }
    }
    var titleEN: String {
        switch self {
        case .liveNow:        return "Live Now"
        case .fileTools:      return "File Tools"
        case .library:        return "Library"
        case .read:           return "Read (TTS)"
        case .fun:            return "Entertainment"
        case .games:          return "Games"
        case .appLauncher:    return "App Launcher"
        case .tools:          return "Tools"
        case .github:         return "GitHub"
        case .settings:       return "Settings"
        case .admin:          return "Admin"
        case .mediaConverter: return "Convert"
        case .messenger:      return "Messaging"
        case .remoteServer:   return "Remote Server"
        case .remoteDesktop:  return "Remote PC Control"
        case .certImport:     return "Signing Cert"
        case .ipaLibrary:     return "IPA Library"
        case .myStore:        return "My Store"
        case .pcRemote:       return "PC Remote"
        case .remotePC:       return "Remote PC (Cloud)"
        }
    }
    var subtitleEN: String {
        switch self {
        case .liveNow:        return "Go live · TikTok · FB · YouTube"
        case .fileTools:      return "PDF · Audio · Scan · Image"
        case .library:        return "Videos · downloaded files"
        case .read:           return "Read text · new voices"
        case .fun:            return "Movies · music · web"
        case .games:          return "Play games in app"
        case .appLauncher:    return "Add your apps · Launch fast"
        case .tools:          return "Images · news · utilities"
        case .github:         return "Upload/delete repo files"
        case .settings:       return "Account · appearance"
        case .admin:          return "Manage users"
        case .mediaConverter: return "Image/Video → GIF · PNG"
        case .messenger:      return "Manual · Auto Web"
        case .remoteServer:   return "SSH · SFTP · Run VPS scripts"
        case .remoteDesktop:  return "View & control PC screen"
        case .certImport:     return "Import .p12 · .mobileprovision"
        case .ipaLibrary:     return "Collect IPAs · Sign via ESign"
        case .myStore:        return "Your own shop · sell"
        case .pcRemote:       return "Trackpad · Keys · Screen"
        case .remotePC:       return "IP+Pass · control via VPS"
        }
    }
    var icon: String {
        switch self {
        case .liveNow:        return "dot.radiowaves.left.and.right"
        case .fileTools:      return "doc.badge.gearshape.fill"
        case .library:        return "clock.arrow.circlepath"
        case .read:           return "speaker.wave.2.fill"
        case .fun:            return "play.tv.fill"
        case .games:          return "gamecontroller.fill"
        case .appLauncher:    return "bolt.heart.fill"
        case .tools:          return "square.grid.2x2.fill"
        case .github:         return "chevron.left.forwardslash.chevron.right"
        case .settings:       return "gearshape.fill"
        case .admin:          return "person.2.badge.gearshape.fill"
        case .mediaConverter: return "wand.and.stars"
        case .messenger:      return "bubble.left.and.bubble.right.fill"
        case .remoteServer:   return "terminal.fill"
        case .remoteDesktop:  return "display"
        case .certImport:     return "checkmark.seal.fill"
        case .ipaLibrary:     return "shippingbox.fill"
        case .myStore:        return "storefront.fill"
        case .pcRemote:       return "desktopcomputer"
        case .remotePC:       return "display"
        }
    }
    var colors: [Color] {
        switch self {
        case .liveNow:        return [Color(red: 0.98, green: 0.2, blue: 0.25), Color(red: 0.8, green: 0.05, blue: 0.2)]
        case .fileTools:      return [Color(red: 0.0, green: 0.7, blue: 0.65), Color(red: 0.0, green: 0.45, blue: 0.7)]
        case .library:        return [Color(red: 0.0, green: 0.6, blue: 0.95), Color(red: 0.0, green: 0.4, blue: 0.85)]
        case .read:           return [Color(red: 0.0, green: 0.78, blue: 0.7), Color(red: 0.0, green: 0.55, blue: 0.7)]
        case .fun:            return [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.75, green: 0.2, blue: 0.55)]
        case .games:          return [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.35, green: 0.3, blue: 0.9)]
        case .appLauncher:    return [Color(red: 1.0, green: 0.35, blue: 0.0), Color(red: 0.9, green: 0.15, blue: 0.0)]
        case .tools:          return [Color(red: 0.95, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.4, blue: 0.1)]
        case .github:         return [Color(red: 0.2, green: 0.22, blue: 0.28), Color(red: 0.1, green: 0.11, blue: 0.15)]
        case .settings:       return [Color(red: 0.4, green: 0.45, blue: 0.55), Color(red: 0.25, green: 0.3, blue: 0.4)]
        case .admin:          return [Color(red: 1.0, green: 0.78, blue: 0.0), Color(red: 0.9, green: 0.55, blue: 0.0)]
        case .mediaConverter: return [Color(red: 0.6, green: 0.1, blue: 0.9), Color(red: 0.9, green: 0.2, blue: 0.6)]
        case .messenger:      return [Color(red: 0.05, green: 0.7, blue: 0.5), Color(red: 0.0, green: 0.5, blue: 0.75)]
        case .remoteServer:   return [Color(red: 0.1, green: 0.5, blue: 0.3), Color(red: 0.05, green: 0.3, blue: 0.5)]
        case .remoteDesktop:  return [Color(red: 0.15, green: 0.35, blue: 0.85), Color(red: 0.1, green: 0.2, blue: 0.55)]
        case .certImport:     return [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.5, blue: 0.35)]
        case .ipaLibrary:     return [Color(red: 0.55, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.3, blue: 0.85)]
        case .myStore:        return [Color(red: 0.0, green: 0.72, blue: 0.5), Color(red: 0.0, green: 0.5, blue: 0.7)]
        case .pcRemote:       return [Color(red: 0.0, green: 0.55, blue: 0.9), Color(red: 0.3, green: 0.2, blue: 0.85)]
        case .remotePC:       return [Color(red: 0.15, green: 0.6, blue: 0.75), Color(red: 0.1, green: 0.35, blue: 0.7)]
        }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct ExploreHubView: View {
    @EnvironmentObject var store: AppStore
    @State private var dest: HubDest?
    @StateObject private var browserModel = BrowserModel()

    private var items: [HubDest] {
        var a: [HubDest] = [.liveNow, .fileTools, .library, .read, .fun, .games, .appLauncher, .tools, .github, .mediaConverter, .messenger, .myStore, .remoteServer, .remoteDesktop, .certImport, .ipaLibrary, .pcRemote, .remotePC, .settings]
        if store.isAdmin { a.append(.admin) }
        return a
    }
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KHeroHeader(icon: "square.grid.2x2.fill",
                                title: store.t("Khám phá", "Explore"),
                                subtitle: store.t("Tất cả tính năng của KENIOS", "All KENIOS features"))

                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(items) { it in
                            Button {
                                dest = it
                                // Báo cho admin biết người dùng đang mở tính năng nào
                                Task { try? await store.api.sendActivity(it.title) }
                            } label: { card(it) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(store.t("Khám phá", "Explore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { ThreeDLogoText(size: 20) } }
            .sheet(item: $dest) { d in destView(d) }
        }
    }

    private func card(_ it: HubDest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: it.icon)
                .font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(it.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: it.colors.first!.opacity(0.4), radius: 8, x: 0, y: 4)
            Text(store.t(it.title, it.titleEN)).font(.headline).foregroundStyle(.primary)
            Text(store.t(it.subtitle, it.subtitleEN)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(18)
    }

    @ViewBuilder
    private func destView(_ d: HubDest) -> some View {
        switch d {
        case .liveNow:        LiveNowHubView()
        case .fileTools:      FileToolsView()
        case .library:        LibraryView()
        case .read:           TTSView()
        case .fun:            MediaWebView(model: browserModel)
        case .games:          GameZoneView()
        case .appLauncher:    AppLauncherView()
        case .tools:          CreatorToolsView()
        case .github:         GitHubView()
        case .settings:       SettingsView()
        case .admin:          AdminView()
        case .mediaConverter: MediaConverterView()
        case .messenger:
            if store.isPro { MessengerHubView().environmentObject(store) }
            else { ProLockCard(feature: store.t("Nhắn tin", "Messaging")) }
        case .remoteServer:
            RemoteServerRootView(baseURL: store.baseURL, token: store.token ?? "")
        case .remoteDesktop:
            RemoteDesktopView()
        case .certImport:
            CertificateImportView()
        case .ipaLibrary:
            IPALibraryView()
        case .myStore:
            MyStoreView()
        case .pcRemote:
            PCRemoteView()
        case .remotePC:
            RemotePCView()
        }
    }
}

// ======================== Live Now — gom Phòng Live + Live Tools (TikTok/FB/YouTube) ========================
struct LiveNowHubView: View {
    @EnvironmentObject var store: AppStore
    @State private var seg = 0   // 0: Phòng Live  ·  1: Phát đa nền tảng

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $seg) {
                Text(store.t("Phòng Live", "Live Rooms")).tag(0)
                Text(store.t("Phát đa nền tảng", "Go Live")).tag(1)
                Text(store.t("Lớp phủ", "Overlay")).tag(2)
                Text(store.t("Máy chủ", "Server Engine")).tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Mỗi view con tự bọc NavigationStack riêng nên hiển thị đầy đủ tiêu đề/thanh công cụ
            if seg == 0 {
                LiveView()
            } else if seg == 1 {
                SocialMediaToolsView(initialSegment: 2)   // mở thẳng Live Tools
            } else if seg == 2 {
                OverlayDesignerView()
            } else {
                // Live Now System Engine — điều khiển FFmpeg/RTMP trên VPS qua SSH
                LiveNowRootView(baseURL: store.baseURL, token: store.token ?? "")
            }
        }
    }
}

// ======================== Chuyển đổi ảnh/video → link GIF/PNG ========================
struct MediaLinkRecord: Codable, Identifiable {
    var id: UUID
    var url: String
    var type: String   // "image" "gif" "png" "jpeg" "webp" "video"
    var name: String?
    var createdAt: Date
    init(url: String, type: String, name: String? = nil) {
        self.id = UUID()
        self.url = url
        self.type = type
        self.name = name
        self.createdAt = Date()
    }
}

struct MediaConverterView: View {
    @EnvironmentObject var store: AppStore
    @State private var inputURL = ""
    @State private var outputFormat = "gif"
    @State private var resultLink = ""
    @State private var converting = false
    @State private var errorMsg: String?
    @State private var picker: PhotosPickerItem?
    @State private var uploading = false
    @AppStorage("mediaLinkHistory") private var historyRaw: String = "[]"

    // Tab: "media" = ảnh/video → link; "audio" = video/âm thanh → mp3 link
    @State private var mode = "media"
    @State private var showAudioPicker = false
    @State private var audioExtracting = false
    @State private var audioResultLink = ""
    @State private var audioError: String?

    private var history: [MediaLinkRecord] {
        (try? JSONDecoder().decode([MediaLinkRecord].self, from: Data(historyRaw.utf8))) ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "wand.and.stars",
                                title: store.t("Chuyển đổi Media", "Media Converter"),
                                subtitle: store.t("Ảnh/Video → link · Trích âm thanh → mp3", "Image/Video → link · Extract audio → mp3"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Tab chọn chế độ
                Section {
                    Picker("", selection: $mode) {
                        Text(store.t("Ảnh/Video → Link", "Image/Video → Link")).tag("media")
                        Text(store.t("Trích âm thanh → mp3", "Extract audio → mp3")).tag("audio")
                    }.pickerStyle(.segmented)
                }

                if mode == "audio" { audioExtractSections }
                else { mediaConvertSections }
            }
            .navigationTitle(store.t("Chuyển đổi Media", "Media Converter"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: picker) { item in
                guard let item else { return }
                Task { await uploadPicked(item) }
            }
            .sheet(isPresented: $showAudioPicker) {
                // Nhận video HOẶC file âm thanh, hiện ô tích (✓) + nút "Mở".
                DocumentPicker(contentTypes: [.movie, .video, .audio], allowsMultipleSelection: true, asCopy: true) { urls in
                    if let url = urls.first { Task { await extractAudioToLink(url) } }
                }.ignoresSafeArea()
            }
        }
    }

    // ===== Tab TRÍCH ÂM THANH: tải video/âm thanh → trích ra mp3 → link =====
    @ViewBuilder private var audioExtractSections: some View {
        Section(store.t("Tải video hoặc file âm thanh", "Upload video or audio file")) {
            Button { showAudioPicker = true } label: {
                HStack {
                    if audioExtracting { ProgressView().padding(.trailing, 4) }
                    Label(audioExtracting ? store.t("Đang trích xuất...", "Extracting...")
                                          : store.t("Chọn video / file âm thanh", "Choose video / audio file"),
                          systemImage: "waveform.badge.plus")
                }
            }.disabled(audioExtracting)
            Text(store.t("Chọn 1 video hoặc file âm thanh → app trích phần âm thanh, tạo file .m4a (mp3) rồi trả về link dùng được ngay (đặt làm âm thanh thông báo, v.v.).",
                         "Pick a video or audio file → the app extracts the audio to an .m4a (mp3) file and returns a ready-to-use link."))
                .font(.caption2).foregroundStyle(.secondary)
        }
        if !audioResultLink.isEmpty {
            Section(store.t("Link âm thanh (mp3)", "Audio link (mp3)")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(audioResultLink).font(.caption).foregroundStyle(store.accentColor).textSelection(.enabled)
                    Button { UIPasteboard.general.string = audioResultLink } label: {
                        Label(store.t("Copy link", "Copy link"), systemImage: "doc.on.doc").font(.caption.bold())
                    }
                }
            }
            Section(store.t("Dùng link này ở đâu", "Where to use this link")) {
                Text(store.t("Copy link rồi dán vào 'Kho âm tùy chỉnh' trong mục Đọc (TTS) để làm âm thanh thông báo (tặng quà/follow/chia sẻ).",
                             "Copy and paste into the custom sound library in Read (TTS) to use as a notification sound."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        if let audioError {
            Section { Text(audioError).foregroundStyle(.red).font(.caption) }
        }
    }

    // ===== Tab ẢNH/VIDEO → LINK (giữ nguyên cũ) =====
    @ViewBuilder private var mediaConvertSections: some View {
        Group {
                Section(store.t("Chọn ảnh/video từ máy → tạo link", "Pick image/video → create link")) {
                    PhotosPicker(selection: $picker, matching: .any(of: [.images, .videos])) {
                        HStack {
                            if uploading { ProgressView().padding(.trailing, 4) }
                            Label(uploading ? store.t("Đang tải lên...", "Uploading...")
                                            : store.t("Chọn ảnh hoặc video", "Choose image or video"),
                                  systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    .disabled(uploading)
                    Text(store.t("Chọn 1 ảnh hoặc video → app tự tải lên máy chủ và trả về link dùng được ngay.",
                                 "Pick 1 image or video → the app uploads it and returns a ready-to-use link."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Hoặc dán link sẵn", "Or paste an existing link")) {
                    TextField(store.t("Dán link ảnh hoặc video...", "Paste image or video link..."), text: $inputURL, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .lineLimit(1...3)
                    Text(store.t("Hoặc dán link ảnh GIF/PNG từ các dịch vụ như Imgur, Giphy, Cloudinary...",
                                 "Or paste a GIF/PNG link from services like Imgur, Giphy, Cloudinary..."))
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section(store.t("Định dạng đầu ra", "Output format")) {
                    Picker(store.t("Định dạng", "Format"), selection: $outputFormat) {
                        Text("GIF").tag("gif")
                        Text("PNG").tag("png")
                        Text("JPEG").tag("jpg")
                        Text("WEBP").tag("webp")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button {
                        convertMedia()
                    } label: {
                        HStack {
                            if converting { ProgressView().padding(.trailing, 4) }
                            Text(converting ? store.t("Đang xử lý...", "Processing...")
                                            : store.t("Tạo link", "Create link") + " \(outputFormat.uppercased())")
                        }
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(inputURL.isEmpty ? Color.gray : store.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputURL.isEmpty || converting)
                }

                if !resultLink.isEmpty {
                    Section(store.t("Link kết quả", "Result link")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(resultLink)
                                .font(.caption).foregroundStyle(store.accentColor)
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = resultLink
                            } label: {
                                Label(store.t("Copy link", "Copy link"), systemImage: "doc.on.doc")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    Section(store.t("Sử dụng link trong cửa hàng", "Use the link in the store")) {
                        Text(store.t("Copy link trên và dán vào mục 'Dán link ảnh/video' khi tạo hoặc sửa sản phẩm trong cửa hàng. Link GIF/PNG sẽ hiển thị trực tiếp trong ứng dụng.",
                                     "Copy the link above and paste it into the 'Paste image/video link' field when creating or editing a store product. GIF/PNG links display directly in the app."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let errorMsg {
                    Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                }

                let records = history
                if !records.isEmpty {
                    Section(header: HStack {
                        Text(store.t("Lịch sử link", "Link history") + " (\(records.count))")
                        Spacer()
                        Button(store.t("Xoá hết", "Clear all")) { historyRaw = "[]" }
                            .font(.caption2).foregroundStyle(.red)
                    }) {
                        ForEach(records) { rec in historyRow(rec) }
                            .onDelete { idx in
                                var r = history
                                r.remove(atOffsets: idx)
                                if let data = try? JSONEncoder().encode(r) {
                                    historyRaw = String(data: data, encoding: .utf8) ?? "[]"
                                }
                            }
                    }
                }

                Section(store.t("Hướng dẫn", "Guide")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(store.t("Dán link ảnh/video (từ internet hoặc Google Drive)", "Paste image/video link (from the internet or Google Drive)"), systemImage: "1.circle.fill")
                        Label(store.t("Chọn định dạng GIF hoặc PNG", "Choose GIF or PNG format"), systemImage: "2.circle.fill")
                        Label(store.t("Bấm tạo link → nhận link có thể dùng trong cửa hàng", "Tap create link → get a link usable in the store"), systemImage: "3.circle.fill")
                        Label(store.t("Bạn cũng có thể dùng Imgur.com, Giphy.com, Cloudinary để host ảnh/GIF miễn phí", "You can also use Imgur.com, Giphy.com, Cloudinary to host images/GIFs for free"), systemImage: "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                }
        }
    }

    /// Trích âm thanh từ video/file âm thanh → xuất .m4a → tải lên → trả link.
    private func extractAudioToLink(_ srcURL: URL) async {
        audioExtracting = true; audioError = nil; audioResultLink = ""
        let access = srcURL.startAccessingSecurityScopedResource()
        defer { if access { srcURL.stopAccessingSecurityScopedResource() } }
        let asset = AVAsset(url: srcURL)
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(Int(Date().timeIntervalSince1970)).m4a")
        try? FileManager.default.removeItem(at: out)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            audioError = store.t("Không tạo được bộ trích xuất.", "Could not create exporter."); audioExtracting = false; return
        }
        export.outputURL = out
        export.outputFileType = .m4a
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { cont.resume() }
        }
        if export.status == .completed, let data = try? Data(contentsOf: out) {
            do {
                let link = try await store.api.mediaUpload(dataBase64: data.base64EncodedString(),
                                                           mime: "audio/mp4", name: out.lastPathComponent)
                audioResultLink = link
            } catch { audioError = error.localizedDescription }
        } else {
            audioError = store.t("Trích xuất âm thanh thất bại (file không có âm thanh hoặc lỗi).",
                                 "Audio extraction failed (no audio track or error).")
        }
        audioExtracting = false
    }

    @ViewBuilder
    private func historyRow(_ rec: MediaLinkRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                typeBadge(rec.type)
                Text(rec.url)
                    .font(.caption2).foregroundStyle(.primary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button {
                    UIPasteboard.general.string = rec.url
                    inputURL = rec.url
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.borderless)
            }
            Text(rec.createdAt, style: .relative)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func typeBadge(_ type: String) -> some View {
        let (label, bgColor): (String, Color) = {
            switch type.lowercased() {
            case "video":       return ("VIDEO", .purple)
            case "gif":         return ("GIF",   .orange)
            case "png":         return ("PNG",   .blue)
            case "jpg", "jpeg": return ("JPEG",  .green)
            case "webp":        return ("WEBP",  .teal)
            default:            return ("IMG",   Color(.systemGray))
            }
        }()
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(bgColor.opacity(0.18))
            .foregroundStyle(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        uploading = true; errorMsg = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMsg = "Không đọc được file đã chọn."; return
            }
            let isVideo = item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
            // Giới hạn kích thước: ảnh 30MB, video 700MB
            let maxBytes = isVideo ? 700 * 1024 * 1024 : 30 * 1024 * 1024
            if data.count > maxBytes {
                let mb = data.count / (1024 * 1024)
                let limit = isVideo ? "700MB" : "30MB"
                errorMsg = "File quá lớn (\(mb)MB). Giới hạn tối đa \(limit) cho \(isVideo ? "video" : "ảnh")."; return
            }
            let mime = isVideo ? "video/mp4" : "image/jpeg"
            let b64 = data.base64EncodedString()
            let url = try await store.api.mediaUpload(dataBase64: b64, mime: mime,
                                                      name: "\(isVideo ? "video" : "img")_\(Int(Date().timeIntervalSince1970))")
            resultLink = url
            inputURL = url
            saveToHistory(url: url, type: isVideo ? "video" : "image")
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func convertMedia() {
        errorMsg = nil
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMsg = "Vui lòng nhập link ảnh hoặc video."; return }

        let lower = trimmed.lowercased()
        if lower.hasSuffix(".\(outputFormat)") || lower.contains(".\(outputFormat)?") {
            resultLink = trimmed
            saveToHistory(url: trimmed, type: outputFormat)
            return
        }

        converting = true
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        var params = "url=\(encoded)"
        switch outputFormat {
        case "gif":   params += "&output=gif&n=-1"
        case "png":   params += "&output=png"
        case "jpg":   params += "&output=jpg&q=90"
        case "webp":  params += "&output=webp&q=90"
        default: break
        }
        let serviceURL = "https://images.weserv.nl/?\(params)"
        resultLink = serviceURL
        saveToHistory(url: serviceURL, type: outputFormat)
        converting = false
    }

    private func saveToHistory(url: String, type: String, name: String? = nil) {
        var records = history
        records.insert(MediaLinkRecord(url: url, type: type, name: name), at: 0)
        if records.count > 50 { records = Array(records.prefix(50)) }
        if let data = try? JSONEncoder().encode(records) {
            historyRaw = String(data: data, encoding: .utf8) ?? "[]"
        }
    }
}

