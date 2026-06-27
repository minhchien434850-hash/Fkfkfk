import SwiftUI
import AVKit
import PhotosUI

// ======================== Helpers chung cho video ========================
/// Tạo URL stream video kèm token ở dạng query (?token=) — đáng tin cậy hơn
/// header tuỳ chỉnh với AVPlayer (header hay bị bỏ qua → video chỉ hiện đen).
func keniosVideoURL(postId: Int, token: String?, baseURL: String) -> URL? {
    var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    if !s.lowercased().hasPrefix("http") { s = "http://" + s }
    while s.hasSuffix("/") { s.removeLast() }
    var comp = URLComponents(string: s + "/posts/\(postId)/video")
    if let token, !token.isEmpty {
        comp?.queryItems = [URLQueryItem(name: "token", value: token)]
    }
    return comp?.url
}

/// Bộ nhớ đệm ảnh thumbnail (khung hình đầu video) để cuộn mượt, đỡ tải lại.
final class VideoThumbCache {
    static let shared = VideoThumbCache()
    private let cache = NSCache<NSNumber, UIImage>()
    func image(for postId: Int) -> UIImage? { cache.object(forKey: NSNumber(value: postId)) }
    func set(_ img: UIImage, for postId: Int) { cache.setObject(img, forKey: NSNumber(value: postId)) }
}

/// Trích khung hình đầu video làm ảnh bìa (poster) cho đẹp & không bị màn đen.
func generateThumbnail(postId: Int, url: URL, completion: @escaping (UIImage?) -> Void) {
    if let cached = VideoThumbCache.shared.image(for: postId) { completion(cached); return }
    DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 720, height: 1280)
        // Lấy khung ~0.3s để tránh khung đen đầu video
        let times = [CMTime(seconds: 0.3, preferredTimescale: 600),
                     CMTime(seconds: 0.0, preferredTimescale: 600)]
        for t in times {
            if let cg = try? gen.copyCGImage(at: t, actualTime: nil) {
                let img = UIImage(cgImage: cg)
                VideoThumbCache.shared.set(img, for: postId)
                DispatchQueue.main.async { completion(img) }
                return
            }
        }
        DispatchQueue.main.async { completion(nil) }
    }
}

// ======================== Video feed — "TikTok của riêng app" ========================
struct VideoFeedView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 0   // 0 = Video, 1 = Reels

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab chọn: Video / Reels
                Picker("", selection: $selectedTab) {
                    Text("Video").tag(0)
                    Text("Reels").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if selectedTab == 0 {
                    VideoListView()
                } else {
                    ReelsFeedView()
                }
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ThreeDLogoText(size: 20) }
                ToolbarItem(placement: .topBarTrailing) { AppearanceMenu() }
            }
        }
    }
}

// ======================== Video list (dạng feed cuộn) ========================
struct VideoListView: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var picker: PhotosPickerItem?
    @State private var caption = ""
    @State private var posting = false
    @State private var showCompose = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KHeroHeader(icon: "play.rectangle.on.rectangle.fill",
                            title: "Video KENIOS",
                            subtitle: "Đăng & xem video ngay trong app của bạn")

                Button { showCompose = true } label: {
                    Label("Đăng video mới", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(store.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if posts.isEmpty && !loading {
                    Text("Chưa có video nào. Hãy đăng video đầu tiên!")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }

                ForEach(posts) { p in postCard(p) }
            }
            .padding()
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCompose) { composeSheet }
    }

    private func postCard(_ p: PostItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2).foregroundStyle(store.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.username).font(.subheadline.bold())
                    if let pid = p.publicId {
                        Text("ID: \(pid)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let uid = p.userId, p.username != store.username {
                    Button { Task { await toggleFollow(p) } } label: {
                        Text((p.following ?? false) ? "Đang theo dõi" : "Theo dõi")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((p.following ?? false) ? Color.gray.opacity(0.3) : store.accentColor)
                            .foregroundStyle((p.following ?? false) ? Color.secondary : Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .id(uid)
                }
                if p.username == store.username || store.isAdmin {
                    Button(role: .destructive) { Task { await delete(p) } } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                }
            }

            // Player nhúng trực tiếp (stream, có ảnh bìa khung hình đầu video)
            InlineVideoPlayer(postId: p.id, token: store.token, baseURL: store.baseURL)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if let cap = p.caption, !cap.isEmpty {
                Text(cap).font(.subheadline)
            }
            HStack(spacing: 16) {
                Button { Task { await like(p) } } label: {
                    Label("\(p.likes)", systemImage: p.liked ? "heart.fill" : "heart")
                        .foregroundStyle(p.liked ? .red : .secondary)
                }
                Spacer()
            }.font(.subheadline)
        }
        .padding()
        .kCard(18)
    }

    private var composeSheet: some View {
        NavigationStack {
            Form {
                Section("Chọn video") {
                    PhotosPicker(selection: $picker, matching: .videos) {
                        Label(picker == nil ? "Chọn video từ máy" : "Đã chọn — đổi video",
                              systemImage: "film")
                    }
                }
                Section("Mô tả") {
                    TextField("Viết mô tả cho video...", text: $caption, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Button { Task { await submitPost() } } label: {
                        HStack {
                            if posting { ProgressView().padding(.trailing, 4) }
                            Text(posting ? "Đang đăng..." : "Đăng video")
                        }
                    }.disabled(picker == nil || posting)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle("Đăng video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { showCompose = false } }
            }
        }
    }

    // MARK: - Actions
    private func load() async {
        loading = true; error = nil
        do { posts = try await store.api.getFeed() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func like(_ p: PostItem) async {
        do {
            let r = try await store.api.likePost(p.id)
            if let idx = posts.firstIndex(where: { $0.id == p.id }) {
                posts[idx] = PostItem(id: p.id, caption: p.caption, likes: r.likes,
                                      createdAt: p.createdAt, fileId: p.fileId,
                                      userId: p.userId, username: p.username,
                                      publicId: p.publicId, name: p.name, mime: p.mime,
                                      liked: r.liked, following: p.following)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func toggleFollow(_ p: PostItem) async {
        guard let uid = p.userId else { return }
        do {
            if p.following ?? false { _ = try await store.api.unfollow(uid) }
            else { _ = try await store.api.follow(uid) }
            await load()
        } catch { self.error = error.localizedDescription }
    }
    private func delete(_ p: PostItem) async {
        do { _ = try await store.api.deletePost(p.id); posts.removeAll { $0.id == p.id } }
        catch { self.error = error.localizedDescription }
    }
    private func submitPost() async {
        guard let picker else { return }
        posting = true; error = nil
        do {
            guard let movie = try await picker.loadTransferable(type: EditMovie.self) else {
                error = "Không đọc được video."; posting = false; return
            }
            let up = try await store.api.uploadFileRaw(
                name: "video_\(Int(Date().timeIntervalSince1970)).mp4",
                category: "video", fileURL: movie.url)
            _ = try await store.api.createPost(fileId: up.id, caption: caption)
            caption = ""; self.picker = nil; showCompose = false
            await load()
        } catch { self.error = error.localizedDescription }
        posting = false
    }
}

// ======================== Player nhúng — ảnh bìa + stream khi bấm phát ========================
struct InlineVideoPlayer: View {
    let postId: Int
    let token: String?
    let baseURL: String

    @State private var player: AVPlayer?
    @State private var thumb: UIImage?
    @State private var isMuted = false

    private var streamURL: URL? { keniosVideoURL(postId: postId, token: token, baseURL: baseURL) }

    var body: some View {
        ZStack {
            Color.black
            // Ảnh bìa khung hình đầu video — luôn hiện trước khi phát
            if let thumb, player == nil {
                Image(uiImage: thumb)
                    .resizable().scaledToFill()
                    .clipped()
            }
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
                // Nút tắt/bật tiếng
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isMuted.toggle(); player.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.subheadline).foregroundStyle(.white)
                                .padding(8).background(.black.opacity(0.45))
                                .clipShape(Circle())
                        }.padding(8)
                    }
                    Spacer()
                }
            } else {
                Button { setupPlayer() } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 6)
                }
            }
        }
        .onAppear { loadThumb() }
    }

    private func loadThumb() {
        guard thumb == nil, let url = streamURL else { return }
        generateThumbnail(postId: postId, url: url) { img in self.thumb = img }
    }

    private func setupPlayer() {
        guard let url = streamURL else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        player = p
        p.play()
    }
}

// ======================== Reels — fullscreen, CUỘN DỌC như TikTok ========================
struct ReelsFeedView: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var currentIndex = 0

    var body: some View {
        GeometryReader { geo in
            Group {
                if loading && posts.isEmpty {
                    ProgressView("Đang tải Reels...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if posts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 56)).foregroundStyle(.secondary)
                        Text("Chưa có Reels nào.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Mẹo xoay: TabView .page mặc định cuộn NGANG → xoay -90° để thành
                    // cuộn DỌC (vuốt lên/xuống), từng ô được xoay bù +90° cho đúng chiều.
                    TabView(selection: $currentIndex) {
                        ForEach(Array(posts.enumerated()), id: \.offset) { idx, p in
                            ReelCard(post: p, token: store.token, baseURL: store.baseURL,
                                     isActive: currentIndex == idx,
                                     onLike: { Task { await like(p) } })
                                .frame(width: geo.size.width, height: geo.size.height)
                                .rotationEffect(.degrees(90))
                                .tag(idx)
                        }
                    }
                    .frame(width: geo.size.height, height: geo.size.width)
                    .rotationEffect(.degrees(-90))
                    .offset(x: (geo.size.width - geo.size.height) / 2,
                            y: (geo.size.height - geo.size.width) / 2)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .topTrailing) {
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .padding(8).background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }

    private func load() async {
        loading = true; error = nil
        do { posts = try await store.api.getFeed() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func like(_ p: PostItem) async {
        do {
            let r = try await store.api.likePost(p.id)
            if let idx = posts.firstIndex(where: { $0.id == p.id }) {
                posts[idx] = PostItem(id: p.id, caption: p.caption, likes: r.likes,
                                      createdAt: p.createdAt, fileId: p.fileId,
                                      userId: p.userId, username: p.username,
                                      publicId: p.publicId, name: p.name, mime: p.mime,
                                      liked: r.liked, following: p.following)
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct ReelCard: View {
    let post: PostItem
    let token: String?
    let baseURL: String
    let isActive: Bool
    var onLike: () -> Void

    @State private var player: AVPlayer?
    @State private var thumb: UIImage?
    @State private var isMuted = false
    @State private var showLikeBurst = false
    @State private var endObserver: NSObjectProtocol?

    private var streamURL: URL? { keniosVideoURL(postId: post.id, token: token, baseURL: baseURL) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Ảnh bìa khung hình đầu video — hiện trong lúc tải/khi chưa phát
            if let thumb {
                Image(uiImage: thumb)
                    .resizable().scaledToFill()
                    .ignoresSafeArea()
            }
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)   // để cử chỉ chạm/cuộn đi tới lớp dưới
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 70)).foregroundStyle(.white.opacity(0.7))
            }

            // Trái tim bay khi chạm 2 lần
            if showLikeBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 110)).foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            }

            // Thông tin bài đăng + nút tương tác
            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.username).font(.headline.bold()).foregroundStyle(.white)
                        if let cap = post.caption, !cap.isEmpty {
                            Text(cap).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    VStack(spacing: 22) {
                        Button(action: onLike) {
                            VStack(spacing: 4) {
                                Image(systemName: post.liked ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundStyle(post.liked ? .red : .white)
                                Text("\(post.likes)").font(.caption).foregroundStyle(.white)
                            }
                        }
                        Button {
                            isMuted.toggle(); player?.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3).foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 56)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        // Chạm 1 lần: tạm dừng / phát ; Chạm 2 lần: thích
        .onTapGesture(count: 2) {
            onLike()
            withAnimation(.spring(response: 0.3)) { showLikeBurst = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                withAnimation { showLikeBurst = false }
            }
        }
        .onTapGesture {
            guard let player else { return }
            if player.timeControlStatus == .paused { player.play() } else { player.pause() }
        }
        .onAppear { loadThumb(); setupPlayer() }
        .onDisappear { teardown() }
        .onChange(of: isActive) { active in
            if active { player?.seek(to: .zero); player?.play() } else { player?.pause() }
        }
    }

    private func loadThumb() {
        guard thumb == nil, let url = streamURL else { return }
        generateThumbnail(postId: post.id, url: url) { img in self.thumb = img }
    }

    private func setupPlayer() {
        guard player == nil, let url = streamURL else { return }
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = isMuted
        // Lặp lại Reels tự động
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            p.seek(to: .zero); p.play()
        }
        player = p
        if isActive { p.play() }
    }

    private func teardown() {
        player?.pause()
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = nil
        player = nil
    }
}
