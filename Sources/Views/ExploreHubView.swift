import SwiftUI
import PhotosUI

// ======================== Khám phá — lưới nút đẹp, gom các tính năng phụ ========================
enum HubDest: String, Identifiable {
    case library, read, fun, games, tools, github, settings, admin, mediaConverter, messenger
    var id: String { rawValue }

    var title: String {
        switch self {
        case .library:        return "Thư viện"
        case .read:           return "Đọc (TTS)"
        case .fun:            return "Giải trí"
        case .games:          return "Trò chơi"
        case .tools:          return "Công cụ"
        case .github:         return "GitHub"
        case .settings:       return "Cài đặt"
        case .admin:          return "Quản trị"
        case .mediaConverter: return "Chuyển đổi"
        case .messenger:      return "Nhắn tin"
        }
    }
    var subtitle: String {
        switch self {
        case .library:        return "Video · file đã tải"
        case .read:           return "Đọc văn bản · giọng mới"
        case .fun:            return "Phim · nhạc · web"
        case .games:          return "Chơi game trong app"
        case .tools:          return "Ảnh · tin tức · tiện ích"
        case .github:         return "Tải/xoá file lên repo"
        case .settings:       return "Tài khoản · giao diện"
        case .admin:          return "Quản lý người dùng"
        case .mediaConverter: return "Ảnh/Video → GIF · PNG"
        case .messenger:      return "Thủ công · Tự động Web"
        }
    }
    var icon: String {
        switch self {
        case .library:        return "clock.arrow.circlepath"
        case .read:           return "speaker.wave.2.fill"
        case .fun:            return "play.tv.fill"
        case .games:          return "gamecontroller.fill"
        case .tools:          return "square.grid.2x2.fill"
        case .github:         return "chevron.left.forwardslash.chevron.right"
        case .settings:       return "gearshape.fill"
        case .admin:          return "person.2.badge.gearshape.fill"
        case .mediaConverter: return "wand.and.stars"
        case .messenger:      return "bubble.left.and.bubble.right.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .library:        return [Color(red: 0.0, green: 0.6, blue: 0.95), Color(red: 0.0, green: 0.4, blue: 0.85)]
        case .read:           return [Color(red: 0.0, green: 0.78, blue: 0.7), Color(red: 0.0, green: 0.55, blue: 0.7)]
        case .fun:            return [Color(red: 0.95, green: 0.3, blue: 0.5), Color(red: 0.75, green: 0.2, blue: 0.55)]
        case .games:          return [Color(red: 0.55, green: 0.4, blue: 0.95), Color(red: 0.35, green: 0.3, blue: 0.9)]
        case .tools:          return [Color(red: 0.95, green: 0.6, blue: 0.1), Color(red: 0.9, green: 0.4, blue: 0.1)]
        case .github:         return [Color(red: 0.2, green: 0.22, blue: 0.28), Color(red: 0.1, green: 0.11, blue: 0.15)]
        case .settings:       return [Color(red: 0.4, green: 0.45, blue: 0.55), Color(red: 0.25, green: 0.3, blue: 0.4)]
        case .admin:          return [Color(red: 1.0, green: 0.78, blue: 0.0), Color(red: 0.9, green: 0.55, blue: 0.0)]
        case .mediaConverter: return [Color(red: 0.6, green: 0.1, blue: 0.9), Color(red: 0.9, green: 0.2, blue: 0.6)]
        case .messenger:      return [Color(red: 0.05, green: 0.7, blue: 0.5), Color(red: 0.0, green: 0.5, blue: 0.75)]
        }
    }
    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct ExploreHubView: View {
    @EnvironmentObject var store: AppStore
    @State private var dest: HubDest?

    private var items: [HubDest] {
        var a: [HubDest] = [.library, .read, .fun, .games, .tools, .github, .mediaConverter, .messenger, .settings]
        if store.isAdmin { a.append(.admin) }
        return a
    }
    private let cols = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    KHeroHeader(icon: "square.grid.2x2.fill",
                                title: "Khám phá",
                                subtitle: "Tất cả tính năng của KENIOS")

                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(items) { it in
                            Button { dest = it } label: { card(it) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Khám phá")
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
            Text(it.title).font(.headline).foregroundStyle(.primary)
            Text(it.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .kCard(18)
    }

    @ViewBuilder
    private func destView(_ d: HubDest) -> some View {
        switch d {
        case .library:        LibraryView()
        case .read:           TTSView()
        case .fun:            MediaWebView()
        case .games:          GameZoneView()
        case .tools:          CreatorToolsView()
        case .github:         GitHubView()
        case .settings:       SettingsView()
        case .admin:          AdminView()
        case .mediaConverter: MediaConverterView()
        case .messenger:      MessengerHubView().environmentObject(store)
        }
    }
}

// ======================== Chuyển đổi ảnh/video → link GIF/PNG ========================
struct MediaConverterView: View {
    @EnvironmentObject var store: AppStore
    @State private var inputURL = ""
    @State private var outputFormat = "gif"
    @State private var resultLink = ""
    @State private var converting = false
    @State private var errorMsg: String?
    @State private var picker: PhotosPickerItem?
    @State private var uploading = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "wand.and.stars",
                                title: "Chuyển đổi Media",
                                subtitle: "Ảnh / Video → GIF · PNG link")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section("Chọn ảnh từ máy → tạo link") {
                    PhotosPicker(selection: $picker, matching: .images) {
                        HStack {
                            if uploading { ProgressView().padding(.trailing, 4) }
                            Label(uploading ? "Đang tải ảnh lên..." : "Chọn ảnh từ thư viện",
                                  systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    .disabled(uploading)
                    Text("Chọn 1 ảnh từ máy → app tự tải lên máy chủ và trả về 1 link dùng được ngay.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Hoặc dán link sẵn") {
                    TextField("Dán link ảnh hoặc video...", text: $inputURL, axis: .vertical)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .lineLimit(1...3)
                    Text("Hoặc dán link ảnh GIF/PNG từ các dịch vụ như Imgur, Giphy, Cloudinary...")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Định dạng đầu ra") {
                    Picker("Định dạng", selection: $outputFormat) {
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
                            Text(converting ? "Đang xử lý..." : "Tạo link \(outputFormat.uppercased())")
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
                    Section("Link kết quả") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(resultLink)
                                .font(.caption).foregroundStyle(store.accentColor)
                                .textSelection(.enabled)
                            Button {
                                UIPasteboard.general.string = resultLink
                            } label: {
                                Label("Copy link", systemImage: "doc.on.doc")
                                    .font(.caption.bold())
                            }
                        }
                    }
                    Section("Sử dụng link trong cửa hàng") {
                        Text("Copy link trên và dán vào mục 'Dán link ảnh/video' khi tạo hoặc sửa sản phẩm trong cửa hàng. Link GIF/PNG sẽ hiển thị trực tiếp trong ứng dụng.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let errorMsg {
                    Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                }

                Section("Hướng dẫn") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Dán link ảnh/video (từ internet hoặc Google Drive)", systemImage: "1.circle.fill")
                        Label("Chọn định dạng GIF hoặc PNG", systemImage: "2.circle.fill")
                        Label("Bấm tạo link → nhận link có thể dùng trong cửa hàng", systemImage: "3.circle.fill")
                        Label("Bạn cũng có thể dùng Imgur.com, Giphy.com, Cloudinary để host ảnh/GIF miễn phí", systemImage: "lightbulb.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Chuyển đổi Media")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: picker) { item in
                guard let item else { return }
                Task { await uploadPicked(item) }
            }
        }
    }

    private func uploadPicked(_ item: PhotosPickerItem) async {
        uploading = true; errorMsg = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMsg = "Không đọc được ảnh đã chọn."; return
            }
            let b64 = data.base64EncodedString()
            let url = try await store.api.mediaUpload(dataBase64: b64, mime: "image/jpeg",
                                                      name: "upload_\(Int(Date().timeIntervalSince1970))")
            resultLink = url
            inputURL = url
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func convertMedia() {
        errorMsg = nil
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMsg = "Vui lòng nhập link ảnh hoặc video."; return }

        // Nếu link đã là GIF/PNG/JPG → trả về trực tiếp
        let lower = trimmed.lowercased()
        if lower.hasSuffix(".\(outputFormat)") || lower.contains(".\(outputFormat)?") {
            resultLink = trimmed
            return
        }

        // Tạo link chuyển đổi qua dịch vụ images.weserv.nl (miễn phí, không cần API key)
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
        converting = false
    }
}

