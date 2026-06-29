import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// ======================== Khám phá — lưới nút đẹp, gom các tính năng phụ ========================
enum HubDest: String, Identifiable {
    case liveNow, fileTools, library, read, fun, games, gameLauncher, tools, github, settings, admin, mediaConverter, messenger, vpn
    var id: String { rawValue }

    var title: String {
        switch self {
        case .liveNow:        return "Live Now"
        case .fileTools:      return "Công cụ tệp"
        case .library:        return "Thư viện"
        case .read:           return "Đọc (TTS)"
        case .fun:            return "Giải trí"
        case .games:          return "Trò chơi"
        case .gameLauncher:   return "Game Launcher"
        case .tools:          return "Công cụ"
        case .github:         return "GitHub"
        case .settings:       return "Cài đặt"
        case .admin:          return "Quản trị"
        case .mediaConverter: return "Chuyển đổi"
        case .messenger:      return "Nhắn tin"
        case .vpn:            return "VPN"
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
        case .gameLauncher:   return "Tối ưu RAM · Mở game nhanh"
        case .tools:          return "Ảnh · tin tức · tiện ích"
        case .github:         return "Tải/xoá file lên repo"
        case .settings:       return "Tài khoản · giao diện"
        case .admin:          return "Quản lý người dùng"
        case .mediaConverter: return "Ảnh/Video → GIF · PNG"
        case .messenger:      return "Thủ công · Tự động Web"
        case .vpn:            return "WireGuard · Bảo mật mạng"
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
        case .gameLauncher:   return "Game Launcher"
        case .tools:          return "Tools"
        case .github:         return "GitHub"
        case .settings:       return "Settings"
        case .admin:          return "Admin"
        case .mediaConverter: return "Convert"
        case .messenger:      return "Messaging"
        case .vpn:            return "VPN"
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
        case .gameLauncher:   return "Optimize RAM · Launch fast"
        case .tools:          return "Images · news · utilities"
        case .github:         return "Upload/delete repo files"
        case .settings:       return "Account · appearance"
        case .admin:          return "Manage users"
        case .mediaConverter: return "Image/Video → GIF · PNG"
        case .messenger:      return "Manual · Auto Web"
        case .vpn:            return "WireGuard · Secure network"
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
        case .gameLauncher:   return "bolt.heart.fill"
        case .tools:          return "square.grid.2x2.fill"
        case .github:         return "chevron.left.forwardslash.chevron.right"
        case .settings:       return "gearshape.fill"
        case .admin:          return "person.2.badge.gearshape.fill"
        case .mediaConverter: return "wand.and.stars"
        case .messenger:      return "bubble.left.and.bubble.right.fill"
        case .vpn:            return "lock.shield.fill"
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
        case .gameLauncher:   return [Color(red: 1.0, green: 0.35, blue: 0.0), Color(red: 0.9, green: 0.15, blue: 0.0)]
        case .tools:          return [Color(red: 0.95, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.4, blue: 0.1)]
        case .github:         return [Color(red: 0.2, green: 0.22, blue: 0.28), Color(red: 0.1, green: 0.11, blue: 0.15)]
        case .settings:       return [Color(red: 0.4, green: 0.45, blue: 0.55), Color(red: 0.25, green: 0.3, blue: 0.4)]
        case .admin:          return [Color(red: 1.0, green: 0.78, blue: 0.0), Color(red: 0.9, green: 0.55, blue: 0.0)]
        case .mediaConverter: return [Color(red: 0.6, green: 0.1, blue: 0.9), Color(red: 0.9, green: 0.2, blue: 0.6)]
        case .messenger:      return [Color(red: 0.05, green: 0.7, blue: 0.5), Color(red: 0.0, green: 0.5, blue: 0.75)]
        case .vpn:            return [Color(red: 0.1, green: 0.5, blue: 0.9), Color(red: 0.05, green: 0.3, blue: 0.7)]
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
        var a: [HubDest] = [.liveNow, .fileTools, .library, .read, .fun, .games, .gameLauncher, .tools, .vpn, .github, .mediaConverter, .messenger, .settings]
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
        case .gameLauncher:   GameLauncherView()
        case .tools:          CreatorToolsView()
        case .github:         GitHubView()
        case .settings:       SettingsView()
        case .admin:          AdminView()
        case .mediaConverter: MediaConverterView()
        case .messenger:
            if store.isPro { MessengerHubView().environmentObject(store) }
            else { ProLockCard(feature: store.t("Nhắn tin", "Messaging")) }
        case .vpn:
            VPNView()
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
            } else {
                OverlayDesignerView()
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

    private var history: [MediaLinkRecord] {
        (try? JSONDecoder().decode([MediaLinkRecord].self, from: Data(historyRaw.utf8))) ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "wand.and.stars",
                                title: store.t("Chuyển đổi Media", "Media Converter"),
                                subtitle: store.t("Ảnh / Video → GIF · PNG link", "Image / Video → GIF · PNG link"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

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
            .navigationTitle(store.t("Chuyển đổi Media", "Media Converter"))
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: picker) { item in
                guard let item else { return }
                Task { await uploadPicked(item) }
            }
        }
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
            // Giới hạn kích thước: ảnh 30MB, video 300MB
            let maxBytes = isVideo ? 300 * 1024 * 1024 : 30 * 1024 * 1024
            if data.count > maxBytes {
                let mb = data.count / (1024 * 1024)
                let limit = isVideo ? "300MB" : "30MB"
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

