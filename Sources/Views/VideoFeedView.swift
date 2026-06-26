import SwiftUI
import AVKit
import PhotosUI

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
    @State private var playingId: Int?

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

            // Player nhúng trực tiếp (stream, không download trước)
            InlineVideoPlayer(postId: p.id, token: store.token, baseURL: store.baseURL)
                .frame(height: 220)
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

// ======================== Player nhúng — stream với Auth header, không download trước ========================
struct InlineVideoPlayer: View {
    let postId: Int
    let token: String?
    let baseURL: String

    @State private var player: AVPlayer?
    @State private var isPlaying = false

    private var streamURL: URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/posts/\(postId)/video")
    }

    var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                Button {
                    setupPlayer()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }

    private func setupPlayer() {
        guard let url = streamURL else { return }
        // Dùng AVURLAsset với Authorization header để stream có auth, không download trước
        var headers: [String: String] = [:]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        player = p
        p.play()
    }
}

// ======================== Reels — dạng fullscreen cuộn dọc ========================
struct ReelsFeedView: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var currentIndex = 0

    var body: some View {
        Group {
            if loading && posts.isEmpty {
                ProgressView("Đang tải Reels...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if posts.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 56)).foregroundStyle(.secondary)
                    Text("Chưa có Reels nào.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.offset) { idx, p in
                        ReelCard(post: p, token: store.token, baseURL: store.baseURL,
                                 isActive: currentIndex == idx) { Task { await like(p) } }
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
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

    private var streamURL: URL? {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return URL(string: s + "/posts/\(post.id)/video")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 70)).foregroundStyle(.white.opacity(0.7))
            }

            // Thông tin bài đăng
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
                    VStack(spacing: 20) {
                        Button(action: onLike) {
                            VStack(spacing: 4) {
                                Image(systemName: post.liked ? "heart.fill" : "heart")
                                    .font(.title2)
                                    .foregroundStyle(post.liked ? .red : .white)
                                Text("\(post.likes)").font(.caption).foregroundStyle(.white)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .onAppear { setupPlayer() }
        .onDisappear { player?.pause(); player = nil }
        .onChange(of: isActive) { active in
            if active { player?.play() } else { player?.pause() }
        }
    }

    private func setupPlayer() {
        guard let url = streamURL else { return }
        var headers: [String: String] = [:]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        // Lặp lại Reels tự động
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: item, queue: .main) { _ in
            p.seek(to: .zero)
            p.play()
        }
        player = p
        if isActive { p.play() }
    }
}
