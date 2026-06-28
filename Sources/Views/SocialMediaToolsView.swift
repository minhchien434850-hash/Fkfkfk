import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import WebKit
import Photos

// Điểm phát Live (RTMP + stream key) lưu lại để phát đa nền tảng
struct LiveTarget: Identifiable, Codable {
    var id = UUID()
    var name: String
    var rtmp: String
    var key: String
}

// Kết quả lấy stream key cho 1 nền tảng (TikTok / Facebook / YouTube)
struct PlatformStreamResult {
    var rtmp: String = ""
    var key: String = ""
    var error: String? = nil
    var ok: Bool { error == nil && !rtmp.isEmpty && !key.isEmpty }
}

// Thông tin hiển thị mỗi nền tảng
struct LivePlatformInfo {
    let id: String        // "tiktok" | "facebook" | "youtube"
    let name: String
    let icon: String
    let loginURL: String
    static let all: [LivePlatformInfo] = [
        .init(id: "tiktok",   name: "TikTok Live",   icon: "play.tv",   loginURL: "https://www.tiktok.com/login"),
        .init(id: "facebook", name: "Facebook Live", icon: "person.2",  loginURL: "https://m.facebook.com/"),
        .init(id: "youtube",  name: "YouTube Live",  icon: "video",     loginURL: "https://m.youtube.com/"),
    ]
}

struct SocialMediaToolsView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedSegment: Int // 0: AI Generator, 1: Downloader, 2: Live Tools

    init(initialSegment: Int = 0) {
        _selectedSegment = State(initialValue: initialSegment)
    }

    // Phát Live đa nền tảng (nhập stream key / link)
    @AppStorage("kenios_live_targets") private var liveTargetsRaw = "[]"
    @State private var ltName = ""
    @State private var ltRtmp = "rtmp://"
    @State private var ltKey = ""
    @State private var ltLink = ""
    
    // Downloader States
    @State private var videoURL = ""
    @State private var videoQuality = "1080"
    @State private var downloading = false
    @State private var downloadedFileId: Int?
    @State private var downloadedFileName: String?
    @State private var downloadedFileSize: Int = 0
    @State private var downloaderError: String?
    @State private var previewURL: URL?
    @State private var savingToPhotos = false
    @State private var saveMessage: String?
    
    // Live Tools States — cookie RIÊNG cho từng nền tảng (lưu lâu dài)
    @AppStorage("live_cookie_tiktok")   private var ckTikTok = ""
    @AppStorage("live_cookie_facebook") private var ckFacebook = ""
    @AppStorage("live_cookie_youtube")  private var ckYouTube = ""
    @State private var selectedPlatforms: Set<String> = ["tiktok", "facebook", "youtube"]
    @State private var streamResults: [String: PlatformStreamResult] = [:]
    // Restream: phát màn hình 1 lần → VPS chia ra nhiều nền tảng
    @State private var restream: RestreamInfo?
    @State private var restreamBusy = false
    @State private var restreamRes = "source"   // source | 1080 | 720 | 480
    @State private var restreamFps = "source"   // source | 60 | 30
    @State private var showBrowser = false
    @State private var browserURL = ""
    @State private var streamError: String?
    @State private var fetchingStream = false
    @State private var browserSiteName = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Banner sang trọng
                KHeroHeader(icon: "globe.badge.ellipsis",
                            title: store.t("Mạng xã hội", "Social"),
                            subtitle: store.t("Sáng tạo nội dung · Tải video · Live đa nền tảng",
                                              "Create content · Download video · Multi-platform live"))
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Segmented picker
                Picker("", selection: $selectedSegment) {
                    Text(store.t("Sửa Video", "Edit Video")).tag(0)
                    Text(store.t("Tải Video", "Download")).tag(1)
                    Text("Live Tools").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedSegment == 0 {
                    if store.isPro { VideoEditorView() }
                    else { ProLockCard(feature: store.t("Sửa video", "Edit video")) }
                } else if selectedSegment == 1 {
                    downloaderPane
                } else {
                    if store.isPro { liveToolsPane }
                    else { ProLockCard(feature: store.t("Live Tools / Stream key", "Live Tools / Stream key")) }
                }
            }
            .navigationTitle(store.t("Mạng xã hội", "Social"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThreeDLogoText(size: 20)
                }
            }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showBrowser) {
                CookieBrowserView(urlString: browserURL) { cookies in
                    setCookie(cookies, for: browserSiteName)   // lưu cookie RIÊNG theo nền tảng
                    saveCookieToLibrary(cookies: cookies, siteName: browserSiteName)
                }
            }
        }
    }

    // MARK: - Downloader Pane
    private var downloaderPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t("Link TikTok · Facebook · Pinterest · YouTube", "TikTok · Facebook · Pinterest · YouTube link")).font(.subheadline).bold()
                    TextField(store.t("Dán link video ở đây...", "Paste video link here..."), text: $videoURL)
                        .padding(12)
                        .kGlass(RoundedRectangle(cornerRadius: 12))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                // Chọn độ phân giải
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t("Độ phân giải", "Resolution")).font(.caption).foregroundStyle(.secondary)
                    Picker(store.t("Độ phân giải", "Resolution"), selection: $videoQuality) {
                        Text("720p").tag("720")
                        Text("1080p").tag("1080")
                        Text("2K").tag("2k")
                        Text("4K").tag("4k")
                        Text(store.t("Cao nhất", "Highest")).tag("best")
                    }
                    .pickerStyle(.segmented)
                }

                // Submit button
                Button {
                    Task { await runDownload() }
                } label: {
                    HStack {
                        if downloading {
                            ProgressView().tint(.white)
                            Text(store.t("Đang cào & tải xuống...", "Fetching & downloading..."))
                        } else {
                            Image(systemName: "arrow.down.circle")
                            Text(store.t("Tải video về hệ thống", "Download video to system"))
                        }
                    }
                    .font(.headline).bold().foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(downloading || videoURL.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(downloading || videoURL.trimmingCharacters(in: .whitespaces).isEmpty)
                
                // Download Success View
                if let fileId = downloadedFileId, let name = downloadedFileName {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        
                        VStack(spacing: 4) {
                            Text("Tải thành công!").font(.headline)
                            Text(name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            Text(humanSize(downloadedFileSize)).font(.caption).foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 12) {
                            // Xem trước
                            Button {
                                Task { await previewDownloaded(fileId) }
                            } label: {
                                Label("Xem trước", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            // Mở mục Khám phá (chứa Thư viện)
                            Button {
                                store.tab = 16 // Khám phá → Thư viện
                            } label: {
                                Label("Khám phá", systemImage: "square.grid.2x2.fill")
                            }
                            .buttonStyle(.bordered)
                        }

                        // Lưu vào Thư viện ảnh của máy (camera roll)
                        Button {
                            Task { await saveToPhotos(fileId) }
                        } label: {
                            HStack {
                                if savingToPhotos { ProgressView().tint(.white) }
                                Image(systemName: "square.and.arrow.down.fill")
                                Text(savingToPhotos ? "Đang lưu vào máy..." : "Lưu vào Thư viện máy")
                            }
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(savingToPhotos ? Color.gray : Theme.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(savingToPhotos)

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.caption)
                                .foregroundStyle(saveMessage.contains("✓") ? .green : .red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.green.opacity(0.2), lineWidth: 1)
                    )
                }
                
                if let err = downloaderError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                
                // Guide/Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 Hướng dẫn sử dụng:").font(.footnote).bold()
                    Text("• Hỗ trợ tải video TikTok không logo bằng cách tự động cào API TikWM.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("• Hỗ trợ tải video Facebook HD/SD trực tiếp từ mã nguồn HTML.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("• Tất cả video tải về sẽ lưu trực tiếp vào mục Tài liệu trong Thư viện của bạn để có thể xem lại bất kỳ lúc nào bằng QuickLook.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .kCard(12)
            }
            .padding()
        }
    }
    
    // MARK: - Live Tools Pane
    private var liveToolsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // ====== Live đa nền tảng cùng lúc — cookie RIÊNG từng nền tảng ======
                VStack(alignment: .leading, spacing: 12) {
                    Text("Live đa nền tảng cùng lúc").font(.headline)
                    Text("Đăng nhập từng nền tảng để lấy cookie RIÊNG, tích chọn nền tảng muốn phát rồi bấm tạo Live MỘT LẦN cho tất cả.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(LivePlatformInfo.all, id: \.id) { p in
                        platformRow(p)
                    }

                    Button {
                        Task { await fetchAllStreamKeys() }
                    } label: {
                        HStack {
                            if fetchingStream { ProgressView().tint(.white); Text("Đang tạo Live...") }
                            else {
                                Image(systemName: "dot.radiowaves.left.and.right")
                                Text("Tạo Live cho \(selectedPlatforms.count) nền tảng đã chọn")
                            }
                        }
                        .font(.headline).bold().foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(fetchingStream || selectedPlatforms.isEmpty ? Color.gray : Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(fetchingStream || selectedPlatforms.isEmpty)

                    Text("💡 App lấy RTMP + Stream Key riêng cho từng nền tảng. Dán vào OBS/Larix (hỗ trợ nhiều đích) để phát CÙNG LÚC tới cả 3 nơi. Kết quả tự lưu xuống mục 'Điểm phát' bên dưới.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(16)

                // Phát MÀN HÌNH → cả 3 nền tảng (VPS chia luồng)
                restreamPane

                // Phát Live đa nền tảng bằng stream key / link (lưu thủ công)
                multiLivePane

                if let err = streamError {
                    Text(err).foregroundStyle(.red).font(.caption).padding(.horizontal)
                }
            }
            .padding()
        }
    }

    // Cookie RIÊNG cho từng nền tảng
    private func cookie(for p: String) -> String {
        switch p {
        case "tiktok":   return ckTikTok
        case "facebook": return ckFacebook
        default:         return ckYouTube
        }
    }
    private func setCookie(_ v: String, for p: String) {
        switch p {
        case "tiktok":   ckTikTok = v
        case "facebook": ckFacebook = v
        case "youtube":  ckYouTube = v
        default:         break
        }
    }

    // Một dòng nền tảng: tích chọn + trạng thái cookie + nút đăng nhập + kết quả
    @ViewBuilder
    private func platformRow(_ p: LivePlatformInfo) -> some View {
        let hasCookie = !cookie(for: p.id).isEmpty
        let selected = selectedPlatforms.contains(p.id)
        let res = streamResults[p.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    if selected { selectedPlatforms.remove(p.id) } else { selectedPlatforms.insert(p.id) }
                } label: {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(selected ? .green : .secondary)
                }
                Image(systemName: p.icon).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.name).font(.subheadline.bold())
                    HStack(spacing: 4) {
                        Image(systemName: hasCookie ? "checkmark.seal.fill" : "exclamationmark.triangle")
                            .font(.caption2).foregroundStyle(hasCookie ? .green : .orange)
                        Text(hasCookie ? "Đã có cookie" : "Chưa đăng nhập")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    browserURL = p.loginURL
                    browserSiteName = p.id
                    showBrowser = true
                } label: {
                    Text(hasCookie ? "Đăng nhập lại" : "Đăng nhập").font(.caption.bold())
                }.buttonStyle(.bordered)
            }
            if let res {
                if res.ok {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Sẵn sàng phát").font(.caption.bold()).foregroundStyle(.green)
                        }
                        keyRow("RTMP", res.rtmp)
                        keyRow("Key", res.key)
                        Button { UIPasteboard.general.string = "Server: \(res.rtmp)\nKey: \(res.key)" } label: {
                            Label("Copy RTMP + Key", systemImage: "doc.on.doc").font(.caption2)
                        }.buttonStyle(.bordered)
                    }
                    .padding(8).background(Color.green.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let e = res.error {
                    Text("✗ \(e)").font(.caption2).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Phát màn hình → cả 3 nền tảng (VPS restream)
    private var okStreamCount: Int { streamResults.values.filter { $0.ok }.count }

    private var restreamPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Phát MÀN HÌNH → cả 3 nền tảng").font(.headline)
            Text("VPS nhận 1 luồng từ điện thoại rồi tự đẩy sang các nền tảng đã lấy key ở trên. Bạn chỉ cần quay màn hình MỘT lần.")
                .font(.caption).foregroundStyle(.secondary)

            if let r = restream, r.running, let ingest = r.ingestUrl {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle().fill(.red).frame(width: 9, height: 9)
                        Text("Đang chia luồng tới \(r.targets ?? 0) nền tảng")
                            .font(.caption.bold()).foregroundStyle(.red)
                    }
                    Text("Chất lượng: \((r.resolution ?? "source") == "source" ? "Gốc" : (r.resolution ?? "") + "p") · FPS: \((r.fps ?? "source") == "source" ? "Gốc" : (r.fps ?? ""))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("URL đẩy luồng (dán vào app quay màn hình):").font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Text(ingest).font(.system(.caption2, design: .monospaced)).lineLimit(2)
                        Spacer()
                        Button { UIPasteboard.general.string = ingest } label: { Image(systemName: "doc.on.doc") }
                    }
                    .padding(8).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
                    Button { Task { await stopRestream() } } label: {
                        HStack { if restreamBusy { ProgressView() }; Text("Tắt Restream") }
                            .font(.subheadline.bold()).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Color.red).clipShape(RoundedRectangle(cornerRadius: 10))
                    }.disabled(restreamBusy)
                }
                .padding(10).background(Color.green.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                // Chỉnh độ phân giải + FPS (VPS mã hoá lại nếu khác "Gốc")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Độ phân giải").font(.caption).foregroundStyle(.secondary)
                    Picker("Độ phân giải", selection: $restreamRes) {
                        Text("Gốc").tag("source")
                        Text("1080p").tag("1080")
                        Text("720p").tag("720")
                        Text("480p").tag("480")
                    }.pickerStyle(.segmented)
                    Text("FPS").font(.caption).foregroundStyle(.secondary)
                    Picker("FPS", selection: $restreamFps) {
                        Text("Gốc").tag("source")
                        Text("60").tag("60")
                        Text("30").tag("30")
                    }.pickerStyle(.segmented)
                    if restreamRes != "source" || restreamFps != "source" {
                        Text("VPS sẽ mã hoá lại để ép mức bạn chọn (tốn CPU hơn). Để 'Gốc' nếu muốn nhẹ & giữ nguyên chất lượng điện thoại.")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }

                Button { Task { await startRestream() } } label: {
                    HStack {
                        if restreamBusy { ProgressView().tint(.white) }
                        Image(systemName: "rectangle.on.rectangle.angled")
                        Text("Bật Restream (\(okStreamCount) đích đã sẵn sàng)")
                    }
                    .font(.subheadline.bold()).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(restreamBusy || okStreamCount == 0 ? Color.gray : Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }.disabled(restreamBusy || okStreamCount == 0)
                Text("⚠️ Cần 'Tạo Live' ở trên trước để có key. VPS phải cài ffmpeg và mở cổng 1935.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Text("📲 Sau khi bật: mở app quay màn hình (Larix/Streamlabs) → dán URL đẩy luồng ở trên → bật quay màn hình → bạn live ra cả 3 nền tảng cùng lúc.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(16)
        .task { restream = try? await store.api.restreamStatus() }
    }

    private func startRestream() async {
        restreamBusy = true; streamError = nil
        defer { restreamBusy = false }
        let targets: [[String: String]] = ["tiktok", "facebook", "youtube"].compactMap { p in
            guard let v = streamResults[p], v.ok else { return nil }
            return ["name": platformName(p), "rtmp": v.rtmp, "key": v.key]
        }
        guard !targets.isEmpty else {
            streamError = "Chưa có nền tảng nào sẵn sàng. Hãy bấm 'Tạo Live' ở trên trước."
            return
        }
        do { restream = try await store.api.restreamStart(targets: targets, resolution: restreamRes, fps: restreamFps) }
        catch { streamError = error.localizedDescription }
    }

    private func stopRestream() async {
        restreamBusy = true
        defer { restreamBusy = false }
        do { restream = try await store.api.restreamStop() }
        catch { streamError = error.localizedDescription }
    }

    // MARK: - Phát Live đa nền tảng (stream key / link)
    private var multiLivePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Phát Live đa nền tảng (stream key / link)").font(.headline)
            Text("Dán sẵn RTMP URL + Stream Key của TikTok / YouTube / Facebook... Lưu nhiều điểm phát rồi copy vào OBS/app phát để live cùng lúc.")
                .font(.caption).foregroundStyle(.secondary)

            // Tách nhanh từ 1 link gộp rtmp://.../streamkey
            VStack(alignment: .leading, spacing: 6) {
                Text("Dán link gộp (rtmp://máy-chủ/.../stream-key)").font(.caption).bold()
                HStack {
                    TextField("rtmp://...", text: $ltLink)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .padding(10).background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button("Tách") { splitLink() }
                        .buttonStyle(.bordered)
                        .disabled(!ltLink.contains("/"))
                }
            }

            TextField("Tên (vd: TikTok của tôi)", text: $ltName)
                .padding(10).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            TextField("RTMP URL (vd: rtmp://...)", text: $ltRtmp)
                .font(.system(.caption, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(10).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            TextField("Stream Key", text: $ltKey)
                .font(.system(.caption, design: .monospaced))
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(10).background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                addTarget()
            } label: {
                Label("Lưu điểm phát", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Theme.accent).foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(ltKey.trimmingCharacters(in: .whitespaces).isEmpty || ltRtmp.count < 8)

            ForEach(liveTargets) { t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red)
                        Text(t.name).font(.subheadline.bold())
                        Spacer()
                        Button(role: .destructive) { removeTarget(t) } label: {
                            Image(systemName: "trash").font(.caption)
                        }
                    }
                    keyRow("RTMP", t.rtmp)
                    keyRow("Key", t.key)
                    Button {
                        UIPasteboard.general.string = "Server: \(t.rtmp)\nKey: \(t.key)"
                    } label: {
                        Label("Copy cả RTMP + Key", systemImage: "doc.on.doc").font(.caption)
                    }.buttonStyle(.bordered)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("📌 iOS không tự đẩy hình từ camera khi app chưa ký. Dùng OBS Studio (máy tính) hoặc app phát RTMP, dán Server + Key vào để live. Có thể lưu nhiều nền tảng để restream.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .kCard(16)
    }

    private func keyRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 42, alignment: .leading)
            Text(value).font(.system(.caption2, design: .monospaced)).lineLimit(1)
            Spacer()
            Button { UIPasteboard.general.string = value } label: { Image(systemName: "doc.on.doc").font(.caption2) }
        }
        .padding(8).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var liveTargets: [LiveTarget] {
        (try? JSONDecoder().decode([LiveTarget].self, from: Data(liveTargetsRaw.utf8))) ?? []
    }
    private func saveTargets(_ list: [LiveTarget]) {
        if let d = try? JSONEncoder().encode(list) {
            liveTargetsRaw = String(data: d, encoding: .utf8) ?? "[]"
        }
    }
    private func splitLink() {
        let link = ltLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let idx = link.lastIndex(of: "/") else { return }
        ltRtmp = String(link[..<idx])
        ltKey = String(link[link.index(after: idx)...])
    }
    private func addTarget() {
        var list = liveTargets
        let name = ltName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "Điểm phát \(list.count + 1)" : ltName
        list.append(LiveTarget(name: name,
                               rtmp: ltRtmp.trimmingCharacters(in: .whitespaces),
                               key: ltKey.trimmingCharacters(in: .whitespaces)))
        saveTargets(list)
        ltName = ""; ltRtmp = "rtmp://"; ltKey = ""; ltLink = ""
    }
    private func removeTarget(_ t: LiveTarget) {
        saveTargets(liveTargets.filter { $0.id != t.id })
    }
    
    // MARK: - Helpers
    private func runDownload() async {
        downloading = true
        downloadedFileId = nil
        downloadedFileName = nil
        downloaderError = nil
        saveMessage = nil
        do {
            let res = try await store.api.socialDownload(url: videoURL, quality: videoQuality)
            downloadedFileId = res.fileId
            downloadedFileName = res.filename
            downloadedFileSize = res.size
            videoURL = ""
        } catch {
            downloaderError = error.localizedDescription
        }
        downloading = false
    }
    
    private func previewDownloaded(_ fileId: Int) async {
        do {
            let (tempURL, filename) = try await store.api.downloadFileRaw(fileId)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let destinationURL = cacheDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)
            self.previewURL = destinationURL
        } catch {
            downloaderError = error.localizedDescription
        }
    }

    // Lưu video/ảnh đã tải về vào Thư viện ảnh của máy (camera roll)
    private func saveToPhotos(_ fileId: Int) async {
        savingToPhotos = true
        saveMessage = nil
        do {
            // Tải file về thư mục tạm
            let (tempURL, filename) = try await store.api.downloadFileRaw(fileId)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let destinationURL = cacheDir.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: tempURL, to: destinationURL)

            // Xin quyền thêm vào Photos
            let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
            }
            guard status == .authorized || status == .limited else {
                saveMessage = "Chưa được cấp quyền lưu vào Thư viện ảnh. Vào Cài đặt > KENIOS > Ảnh để bật."
                savingToPhotos = false
                return
            }

            let ext = (filename as NSString).pathExtension.lowercased()
            let isImage = ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext)

            try await PHPhotoLibrary.shared().performChanges {
                if isImage {
                    PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: destinationURL)
                } else {
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)
                }
            }
            saveMessage = isImage ? "Đã lưu ảnh vào Thư viện máy ✓" : "Đã lưu video vào Thư viện máy ✓"
        } catch {
            saveMessage = "Lưu thất bại: \(error.localizedDescription)"
        }
        savingToPhotos = false
    }

    /// Lấy RTMP + Stream Key cho TẤT CẢ nền tảng đã tích chọn (mỗi nền tảng dùng cookie riêng).
    private func fetchAllStreamKeys() async {
        fetchingStream = true
        streamError = nil
        for p in ["tiktok", "facebook", "youtube"] where selectedPlatforms.contains(p) {
            let ck = cookie(for: p)
            if ck.isEmpty {
                streamResults[p] = PlatformStreamResult(error: "Chưa có cookie — hãy bấm Đăng nhập nền tảng này.")
                continue
            }
            do {
                let res: StreamKeyResponse
                switch p {
                case "tiktok":   res = try await store.api.getTikTokStreamKey(cookies: ck)
                case "facebook": res = try await store.api.getFacebookStreamKey(cookies: ck)
                default:         res = try await store.api.getYouTubeStreamKey(cookies: ck)
                }
                streamResults[p] = PlatformStreamResult(rtmp: res.rtmpUrl, key: res.streamKey)
                addTargetDirect(name: platformName(p), rtmp: res.rtmpUrl, key: res.streamKey)
            } catch {
                streamResults[p] = PlatformStreamResult(error: error.localizedDescription)
            }
        }
        fetchingStream = false
    }

    private func platformName(_ p: String) -> String {
        LivePlatformInfo.all.first { $0.id == p }?.name ?? p
    }

    /// Lưu thẳng 1 điểm phát vào danh sách (thay điểm cũ cùng tên) để restream/copy.
    private func addTargetDirect(name: String, rtmp: String, key: String) {
        guard !rtmp.isEmpty, !key.isEmpty else { return }
        var list = liveTargets
        list.removeAll { $0.name == name }
        list.append(LiveTarget(name: name, rtmp: rtmp, key: key))
        saveTargets(list)
    }
    
    private func saveCookieToLibrary(cookies: String, siteName: String) {
        Task {
            do {
                let filename = "cookie_\(siteName)_\(Int(Date().timeIntervalSince1970)).txt"
                let dataB64 = Data(cookies.utf8).base64EncodedString()
                _ = try await store.api.uploadFile(name: filename, category: "document", dataBase64: dataB64)
            } catch {
                print("Error saving cookie: \(error)")
            }
        }
    }
    
    private func humanSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
