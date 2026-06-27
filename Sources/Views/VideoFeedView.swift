import SwiftUI
import AVKit
import PhotosUI
import UIKit

// ======================== Helpers chung cho video ========================
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

final class VideoThumbCache {
    static let shared = VideoThumbCache()
    private let cache = NSCache<NSNumber, UIImage>()
    func image(for postId: Int) -> UIImage? { cache.object(forKey: NSNumber(value: postId)) }
    func set(_ img: UIImage, for postId: Int) { cache.setObject(img, forKey: NSNumber(value: postId)) }
}

func generateThumbnail(postId: Int, url: URL, completion: @escaping (UIImage?) -> Void) {
    if let cached = VideoThumbCache.shared.image(for: postId) { completion(cached); return }
    DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 720, height: 1280)
        for t in [CMTime(seconds: 0.3, preferredTimescale: 600), CMTime(seconds: 0.0, preferredTimescale: 600)] {
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

// ======================== Wrapper để dùng với .sheet(item:) ========================
struct PostIDWrapper: Identifiable { let id: Int }
struct ProfileIDWrapper: Identifiable { let id: Int }

// ======================== Main container ========================
struct VideoFeedView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab = 1   // 0=Của tôi, 1=Feed, 2=Reels
    @State private var profileSheet: ProfileIDWrapper?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(store.t("Của tôi", "My Videos")).tag(0)
                    Text("Feed").tag(1)
                    Text("Reels").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if selectedTab == 0 {
                    MyVideosView()
                } else {
                    VideoListView(onOpenProfile: { uid in
                        profileSheet = ProfileIDWrapper(id: uid)
                    })
                }
            }
            .navigationTitle(store.t("Video", "Video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ThreeDLogoText(size: 20) }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Button {
                            if let uid = store.userId {
                                profileSheet = ProfileIDWrapper(id: uid)
                            }
                        } label: {
                            Image(systemName: "person.crop.circle").font(.title3)
                        }
                        AppearanceMenu()
                    }
                }
            }
            .sheet(item: $profileSheet) { wrapper in
                VideoProfileView(userId: wrapper.id)
                    .environmentObject(store)
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedTab == 2 },
            set: { if !$0 { selectedTab = 1 } }
        )) {
            ReelsFeedView().environmentObject(store)
        }
    }
}

// ======================== My Videos — lưới riêng tư ========================
struct MyVideosView: View {
    @EnvironmentObject var store: AppStore
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showCompose = false
    @State private var detailPost: PostItem?

    private let columns = [GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2),
                            GridItem(.flexible(), spacing: 2)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button { showCompose = true } label: {
                    Label(store.t("Đăng video", "Post video"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(store.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()

                if loading && posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.caption).padding()
                }
                if posts.isEmpty && !loading {
                    VStack(spacing: 12) {
                        Image(systemName: "play.rectangle.on.rectangle")
                            .font(.system(size: 44)).foregroundStyle(.secondary)
                        Text(store.t("Chưa có video nào. Hãy đăng video đầu tiên!",
                                     "No videos yet. Post your first one!"))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }

                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(posts) { p in
                        Button { detailPost = p } label: {
                            VideoGridCell(post: p, token: store.token, baseURL: store.baseURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCompose) {
            ComposeVideoView { await load() }
                .environmentObject(store)
        }
        .fullScreenCover(item: $detailPost) { p in
            VideoDetailView(post: p) { detailPost = nil; await load() }
                .environmentObject(store)
        }
    }

    private func load() async {
        loading = true; error = nil
        do { posts = try await store.api.getMyPosts() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
}

// ======================== Ô video trong lưới ========================
struct VideoGridCell: View {
    let post: PostItem
    let token: String?
    let baseURL: String
    @State private var thumb: UIImage?

    private var streamURL: URL? { keniosVideoURL(postId: post.id, token: token, baseURL: baseURL) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            if let thumb {
                Image(uiImage: thumb).resizable().scaledToFill()
            } else {
                Image(systemName: "play.fill")
                    .font(.title3).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Badge riêng tư / lượt xem
            HStack(spacing: 3) {
                if post.isPublic != true {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "eye").font(.system(size: 9)).foregroundStyle(.white)
                Text("\(post.views ?? 0)").font(.system(size: 9)).foregroundStyle(.white)
            }
            .padding(.horizontal, 4).padding(.bottom, 3)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            )
        }
        .aspectRatio(9/16, contentMode: .fill)
        .clipped()
        .onAppear {
            guard thumb == nil, let url = streamURL else { return }
            generateThumbnail(postId: post.id, url: url) { img in self.thumb = img }
        }
    }
}

// ======================== Chi tiết video (full-screen) ========================
struct VideoDetailView: View {
    let post: PostItem
    var onDeleted: () async -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var player: AVPlayer?
    @State private var likes: Int
    @State private var liked: Bool
    @State private var views: Int
    @State private var showComments = false
    @State private var error: String?
    @State private var deleting = false

    init(post: PostItem, onDeleted: @escaping () async -> Void) {
        self.post = post
        self.onDeleted = onDeleted
        _likes = State(initialValue: post.likes)
        _liked = State(initialValue: post.liked)
        _views = State(initialValue: post.views ?? 0)
    }

    private var isOwn: Bool { store.userId == post.userId || store.isAdmin }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                Button { setupPlayer() } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 72)).foregroundStyle(.white.opacity(0.85))
                }
            }

            // Overlay thông tin + nút
            VStack {
                // Nav bar thủ công (toolbar không hiển thị tốt trên fullScreenCover không có NavigationStack)
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold()).foregroundStyle(.white)
                            .padding(10).background(Circle().fill(.black.opacity(0.35)))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 56)

                Spacer()

                HStack(alignment: .bottom, spacing: 0) {
                    // Info bên trái
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.username).font(.headline.bold()).foregroundStyle(.white)
                        if let cap = post.caption, !cap.isEmpty {
                            Text(cap).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(3)
                        }
                        HStack(spacing: 14) {
                            HStack(spacing: 4) {
                                Image(systemName: "eye").font(.caption)
                                Text("\(views)").font(.caption)
                            }.foregroundStyle(.white.opacity(0.8))
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill").foregroundStyle(.red).font(.caption)
                                Text("\(likes)").font(.caption)
                            }.foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.leading, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Nút tương tác bên phải
                    VStack(spacing: 22) {
                        Button { Task { await like() } } label: {
                            VStack(spacing: 4) {
                                Image(systemName: liked ? "heart.fill" : "heart")
                                    .font(.title2).foregroundStyle(liked ? .red : .white)
                                Text("\(likes)").font(.caption2).foregroundStyle(.white)
                            }
                        }
                        Button { showComments = true } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right").font(.title2).foregroundStyle(.white)
                                Text("\(post.comments ?? 0)").font(.caption2).foregroundStyle(.white)
                            }
                        }
                        Button { shareVideo() } label: {
                            Image(systemName: "square.and.arrow.up").font(.title2).foregroundStyle(.white)
                        }
                        if isOwn {
                            Button(role: .destructive) { Task { await delete() } } label: {
                                if deleting {
                                    ProgressView().tint(.white).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "trash").font(.title2).foregroundStyle(.red)
                                }
                            }
                            .disabled(deleting)
                        }
                    }
                    .padding(.trailing, 16)
                }
                .padding(.bottom, 50)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .padding(8).background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .onAppear { setupPlayer(); Task { await countView() } }
        .onDisappear { player?.pause() }
        .sheet(isPresented: $showComments) {
            PostCommentsView(postId: post.id).environmentObject(store)
        }
    }

    private func setupPlayer() {
        guard player == nil,
              let url = keniosVideoURL(postId: post.id, token: store.token, baseURL: store.baseURL)
        else { return }
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }

    private func like() async {
        do {
            let r = try await store.api.likePost(post.id)
            likes = r.likes; liked = r.liked
        } catch { self.error = error.localizedDescription }
    }

    private func delete() async {
        deleting = true
        do {
            _ = try await store.api.deletePost(post.id)
            player?.pause()
            dismiss()
            await onDeleted()
        } catch { self.error = error.localizedDescription }
        deleting = false
    }

    private func countView() async {
        views += 1
        try? await store.api.incrementView(post.id)
    }

    private func shareVideo() {
        guard let url = keniosVideoURL(postId: post.id, token: nil, baseURL: store.baseURL) else { return }
        let items: [Any] = [post.caption ?? "", url]
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?
            .windows.first?.rootViewController?.present(vc, animated: true)
    }
}

// ======================== Đăng video mới ========================
struct ComposeVideoView: View {
    var onDone: () async -> Void
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var picker: PhotosPickerItem?
    @State private var caption = ""
    @State private var isPublic = true
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("Chọn video", "Choose video")) {
                    PhotosPicker(selection: $picker, matching: .videos) {
                        Label(picker == nil
                              ? store.t("Chọn video từ máy", "Choose video from device")
                              : store.t("Đã chọn — đổi video", "Selected — change video"),
                              systemImage: "film")
                    }
                }
                Section(store.t("Mô tả", "Description")) {
                    TextField(store.t("Viết mô tả cho video...", "Write a caption..."),
                              text: $caption, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle(store.t("Công khai (hiện trên Reels & Feed)", "Public (visible in Reels & Feed)"),
                           isOn: $isPublic)
                }
                Section {
                    Button { Task { await submit() } } label: {
                        HStack {
                            if posting { ProgressView().padding(.trailing, 4) }
                            Text(posting ? store.t("Đang đăng...", "Posting...")
                                        : store.t("Đăng video", "Post video"))
                        }
                    }
                    .disabled(picker == nil || posting)
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .navigationTitle(store.t("Đăng video", "Post video"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        guard let picker else { return }
        posting = true; error = nil
        do {
            guard let movie = try await picker.loadTransferable(type: EditMovie.self) else {
                error = store.t("Không đọc được video.", "Cannot read video.")
                posting = false; return
            }
            let up = try await store.api.uploadFileRaw(
                name: "video_\(Int(Date().timeIntervalSince1970)).mp4",
                category: "video", fileURL: movie.url)
            _ = try await store.api.createPost(fileId: up.id, caption: caption, isPublic: isPublic)
            self.picker = nil; caption = ""
            dismiss()
            await onDone()
        } catch { self.error = error.localizedDescription }
        posting = false
    }
}

// ======================== Bình luận ========================
struct PostCommentsView: View {
    let postId: Int
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var comments: [PostComment] = []
    @State private var loading = false
    @State private var newComment = ""
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if loading && comments.isEmpty {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if comments.isEmpty {
                        Text(store.t("Chưa có bình luận.", "No comments yet."))
                            .foregroundStyle(.secondary).font(.caption)
                    } else {
                        ForEach(comments) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(c.username).font(.caption.bold())
                                Text(c.content).font(.subheadline)
                            }
                            .swipeActions(edge: .trailing) {
                                if c.userId == store.userId || store.isAdmin {
                                    Button(role: .destructive) { Task { await deleteComment(c) } } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()
                HStack(spacing: 10) {
                    TextField(store.t("Viết bình luận...", "Write a comment..."), text: $newComment)
                        .textFieldStyle(.roundedBorder)
                    Button { Task { await postComment() } } label: {
                        if posting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(store.accentColor)
                        }
                    }
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty || posting)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .navigationTitle(store.t("Bình luận", "Comments"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        do { comments = try await store.api.getComments(postId) }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func postComment() async {
        let text = newComment.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        posting = true
        do {
            let c = try await store.api.addComment(postId: postId, content: text)
            comments.append(c)
            newComment = ""
        } catch { self.error = error.localizedDescription }
        posting = false
    }

    private func deleteComment(_ c: PostComment) async {
        do {
            _ = try await store.api.deleteComment(c.id)
            comments.removeAll { $0.id == c.id }
        } catch { self.error = error.localizedDescription }
    }
}

// ======================== Trang cá nhân ========================
struct VideoProfileView: View {
    let userId: Int
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var profile: UserProfile?
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showEdit = false
    @State private var editPublicId = ""
    @State private var editBio = ""
    @State private var saving = false
    @State private var avatarPicker: PhotosPickerItem?
    @State private var uploadingAvatar = false

    private var isOwnProfile: Bool { store.userId == userId }
    private let cols = [GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 14) {
                        // Avatar
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let urlStr = profile?.avatarUrl, let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable().scaledToFill()
                                        } else {
                                            Circle().fill(store.accentColor.opacity(0.2))
                                                .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(store.accentColor))
                                        }
                                    }
                                } else {
                                    Circle().fill(store.accentColor.opacity(0.2))
                                        .overlay(Image(systemName: "person.fill").font(.title).foregroundStyle(store.accentColor))
                                }
                            }
                            .frame(width: 84, height: 84)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(store.accentColor.opacity(0.4), lineWidth: 2))

                            if isOwnProfile {
                                PhotosPicker(selection: $avatarPicker, matching: .images) {
                                    ZStack {
                                        Circle().fill(store.accentColor).frame(width: 26, height: 26)
                                        if uploadingAvatar {
                                            ProgressView().scaleEffect(0.5).tint(.white)
                                        } else {
                                            Image(systemName: "camera.fill").font(.system(size: 11)).foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        VStack(spacing: 4) {
                            Text(profile?.username ?? "...").font(.title3.bold())
                            if let pid = profile?.publicId, !pid.isEmpty {
                                Text("@\(pid)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            if let bio = profile?.bio, !bio.isEmpty {
                                Text(bio).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                            }
                        }

                        // Stats
                        if let p = profile {
                            HStack(spacing: 0) {
                                statCell(value: p.posts, label: store.t("Video", "Videos"))
                                Divider().frame(height: 30)
                                statCell(value: p.followers, label: store.t("Người theo", "Followers"))
                                Divider().frame(height: 30)
                                statCell(value: p.following, label: store.t("Đang theo", "Following"))
                                Divider().frame(height: 30)
                                statCell(value: p.totalLikes ?? 0, label: store.t("Thích", "Likes"))
                            }
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }

                        // Nút hành động
                        if isOwnProfile {
                            Button { showEdit = true } label: {
                                Text(store.t("Chỉnh sửa hồ sơ", "Edit profile"))
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(store.accentColor, lineWidth: 1.5))
                                    .foregroundStyle(store.accentColor)
                            }
                            .padding(.horizontal)
                        } else if let p = profile {
                            Button { Task { await toggleFollow() } } label: {
                                Text(p.isFollowing
                                     ? store.t("Đang theo dõi", "Following")
                                     : store.t("Theo dõi", "Follow"))
                                    .font(.subheadline.bold())
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .background(p.isFollowing ? Color(.systemGray5) : store.accentColor)
                                    .foregroundStyle(p.isFollowing ? Color.secondary : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 20)

                    if let error {
                        Text(error).font(.caption).foregroundStyle(.red).padding()
                    }

                    Divider().padding(.bottom, 2)

                    // Lưới video
                    if loading && posts.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if posts.isEmpty {
                        Text(store.t("Chưa có video công khai.", "No public videos."))
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        LazyVGrid(columns: cols, spacing: 2) {
                            ForEach(posts) { p in
                                VideoGridCell(post: p, token: store.token, baseURL: store.baseURL)
                                    .aspectRatio(9/16, contentMode: .fill).clipped()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isOwnProfile ? store.t("Hồ sơ của tôi", "My Profile")
                                          : (profile?.username ?? store.t("Hồ sơ", "Profile")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.bold())
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showEdit) { editSheet }
        .onChange(of: avatarPicker) { item in
            if let item { Task { await uploadAvatar(item) } }
        }
    }

    @ViewBuilder
    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section(store.t("ID công khai", "Public ID")) {
                    TextField("@id", text: $editPublicId)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section(store.t("Giới thiệu", "Bio")) {
                    TextField(store.t("Viết giới thiệu bản thân...", "Write a bio..."),
                              text: $editBio, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Button { Task { await saveProfile() } } label: {
                        HStack {
                            if saving { ProgressView().padding(.trailing, 4) }
                            Text(saving ? store.t("Đang lưu...", "Saving...")
                                       : store.t("Lưu thay đổi", "Save changes"))
                        }
                    }
                    .disabled(saving)
                }
            }
            .navigationTitle(store.t("Chỉnh sửa hồ sơ", "Edit profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(store.t("Đóng", "Close")) { showEdit = false }
                }
            }
        }
        .onAppear {
            editPublicId = profile?.publicId ?? ""
            editBio = profile?.bio ?? ""
        }
    }

    private func load() async {
        loading = true; error = nil
        do {
            if isOwnProfile {
                async let prof = store.api.myProfile()
                async let vids = store.api.getMyPosts()
                profile = try await prof
                posts = try await vids
            } else {
                async let prof = store.api.userProfile(userId)
                async let vids = store.api.getUserPosts(userId)
                profile = try await prof
                posts = try await vids
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func toggleFollow() async {
        guard let p = profile else { return }
        do {
            if p.isFollowing { _ = try await store.api.unfollow(userId) }
            else { _ = try await store.api.follow(userId) }
            await load()
        } catch { self.error = error.localizedDescription }
    }

    private func saveProfile() async {
        saving = true
        do {
            _ = try await store.api.updateProfile(
                publicId: editPublicId.isEmpty ? nil : editPublicId,
                avatarUrl: nil,
                bio: editBio.isEmpty ? nil : editBio)
            if !editPublicId.isEmpty { store.publicId = editPublicId }
            await load()
            showEdit = false
        } catch { self.error = error.localizedDescription }
        saving = false
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploadingAvatar = true
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                uploadingAvatar = false; return
            }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("avatar_upload.jpg")
            try data.write(to: tmp)
            let up = try await store.api.uploadFileRaw(name: "avatar.jpg", category: "image", fileURL: tmp)
            try? FileManager.default.removeItem(at: tmp)
            var base = store.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.lowercased().hasPrefix("http") { base = "http://" + base }
            while base.hasSuffix("/") { base.removeLast() }
            let avatarUrl = "\(base)/files/\(up.id)/download"
            _ = try await store.api.updateProfile(publicId: nil, avatarUrl: avatarUrl, bio: nil)
            await load()
        } catch {}
        uploadingAvatar = false
    }
}

// ======================== Feed công khai ========================
struct VideoListView: View {
    var onOpenProfile: ((Int) -> Void)?
    @EnvironmentObject var store: AppStore
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var showCompose = false
    @State private var commentsFor: PostIDWrapper?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KHeroHeader(icon: "play.rectangle.on.rectangle.fill",
                            title: store.t("Video KENIOS", "KENIOS Video"),
                            subtitle: store.t("Đăng & xem video ngay trong app của bạn",
                                              "Post & watch videos right in your app"))

                Button { showCompose = true } label: {
                    Label(store.t("Đăng video mới", "New video"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(store.accentColor).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                if posts.isEmpty && !loading {
                    Text(store.t("Chưa có video nào. Hãy đăng video đầu tiên!",
                                 "No videos yet. Post the first one!"))
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 30)
                }

                ForEach(posts) { p in postCard(p) }
            }
            .padding()
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCompose) {
            ComposeVideoView { await load() }.environmentObject(store)
        }
        .sheet(item: $commentsFor) { w in
            PostCommentsView(postId: w.id).environmentObject(store)
        }
    }

    private func postCard(_ p: PostItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: avatar + tên + nút follow/xoá
            HStack {
                Button {
                    if let uid = p.userId { onOpenProfile?(uid) }
                } label: {
                    HStack(spacing: 8) {
                        if let urlStr = p.avatarUrl, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                        .frame(width: 36, height: 36).clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title2).foregroundStyle(store.accentColor)
                                }
                            }
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title2).foregroundStyle(store.accentColor)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.username).font(.subheadline.bold())
                            if let pid = p.publicId {
                                Text("@\(pid)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if let uid = p.userId, p.username != store.username {
                    Button { Task { await toggleFollow(p) } } label: {
                        Text((p.following ?? false)
                             ? store.t("Đang theo dõi", "Following")
                             : store.t("Theo dõi", "Follow"))
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background((p.following ?? false) ? Color.gray.opacity(0.3) : store.accentColor)
                            .foregroundStyle((p.following ?? false) ? Color.secondary : Color.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain).id(uid)
                }
                if p.username == store.username || store.isAdmin {
                    Button(role: .destructive) { Task { await delete(p) } } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                }
            }

            InlineVideoPlayer(postId: p.id, token: store.token, baseURL: store.baseURL)
                .frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if let cap = p.caption, !cap.isEmpty {
                Text(cap).font(.subheadline)
            }

            // Thanh tương tác
            HStack(spacing: 16) {
                Button { Task { await like(p) } } label: {
                    Label("\(p.likes)", systemImage: p.liked ? "heart.fill" : "heart")
                        .foregroundStyle(p.liked ? .red : .secondary)
                }
                Button { commentsFor = PostIDWrapper(id: p.id) } label: {
                    Label("\(p.comments ?? 0)", systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                Button { share(p) } label: {
                    Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                }
                Spacer()
                if let v = p.views {
                    Label("\(v)", systemImage: "eye").font(.caption).foregroundStyle(.secondary)
                }
            }.font(.subheadline)
        }
        .padding()
        .kCard(18)
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
                posts[idx].likes = r.likes
                posts[idx].liked = r.liked
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

    private func share(_ p: PostItem) {
        guard let url = keniosVideoURL(postId: p.id, token: nil, baseURL: store.baseURL) else { return }
        let vc = UIActivityViewController(activityItems: [p.caption ?? "", url], applicationActivities: nil)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?
            .windows.first?.rootViewController?.present(vc, animated: true)
    }
}

// ======================== Player nhúng trong card ========================
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
            if let thumb, player == nil {
                Image(uiImage: thumb).resizable().scaledToFill().clipped()
            }
            if let player {
                VideoPlayer(player: player)
                    .onDisappear { player.pause() }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isMuted.toggle(); player.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.subheadline).foregroundStyle(.white)
                                .padding(8).background(.black.opacity(0.45)).clipShape(Circle())
                        }.padding(8)
                    }
                    Spacer()
                }
            } else {
                Button { setupPlayer() } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60)).foregroundStyle(.white.opacity(0.95)).shadow(radius: 6)
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
        p.isMuted = isMuted; player = p; p.play()
    }
}

// ======================== Reels — fullscreen cuộn dọc ========================
struct ReelsFeedView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var currentIndex = 0
    @State private var commentsFor: PostIDWrapper?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                if loading && posts.isEmpty {
                    ProgressView(store.t("Đang tải Reels...", "Loading Reels..."))
                        .tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if posts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 56)).foregroundStyle(.secondary)
                        Text(store.t("Chưa có Reels nào.", "No Reels yet."))
                            .foregroundStyle(.secondary)
                        Button(store.t("Đóng", "Close")) { dismiss() }.foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(posts.enumerated()), id: \.offset) { idx, p in
                            ReelCard(post: p, token: store.token, baseURL: store.baseURL,
                                     isActive: currentIndex == idx,
                                     onLike: { Task { await like(p) } },
                                     onComment: { commentsFor = PostIDWrapper(id: p.id) })
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
            .ignoresSafeArea()

            // Nút đóng
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2).foregroundStyle(.white.opacity(0.9))
                        .background(Circle().fill(.black.opacity(0.35)).padding(2))
                        .shadow(radius: 4)
                }
                .padding(.trailing, 16).padding(.top, 60)
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .padding(8).background(.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)
            }
        }
        .task { await load() }
        .sheet(item: $commentsFor) { w in
            PostCommentsView(postId: w.id).environmentObject(store)
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
                posts[idx].likes = r.likes
                posts[idx].liked = r.liked
            }
        } catch { self.error = error.localizedDescription }
    }
}

// ======================== ReelCard ========================
struct ReelCard: View {
    let post: PostItem
    let token: String?
    let baseURL: String
    let isActive: Bool
    var onLike: () -> Void
    var onComment: () -> Void

    @State private var player: AVPlayer?
    @State private var thumb: UIImage?
    @State private var isMuted = false
    @State private var showLikeBurst = false
    @State private var endObserver: NSObjectProtocol?

    private var streamURL: URL? { keniosVideoURL(postId: post.id, token: token, baseURL: baseURL) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let thumb {
                Image(uiImage: thumb).resizable().scaledToFill().ignoresSafeArea()
            }
            if let player {
                VideoPlayer(player: player).ignoresSafeArea().allowsHitTesting(false)
            } else {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 70)).foregroundStyle(.white.opacity(0.7))
            }

            if showLikeBurst {
                Image(systemName: "heart.fill")
                    .font(.system(size: 110)).foregroundStyle(.red)
                    .transition(.scale.combined(with: .opacity))
            }

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.username).font(.headline.bold()).foregroundStyle(.white)
                        if let cap = post.caption, !cap.isEmpty {
                            Text(cap).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(2)
                        }
                        if let v = post.views {
                            HStack(spacing: 3) {
                                Image(systemName: "eye").font(.caption2)
                                Text("\(v)").font(.caption2)
                            }.foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    Spacer()
                    VStack(spacing: 22) {
                        // Like
                        Button(action: onLike) {
                            VStack(spacing: 4) {
                                Image(systemName: post.liked ? "heart.fill" : "heart")
                                    .font(.title2).foregroundStyle(post.liked ? .red : .white)
                                Text("\(post.likes)").font(.caption).foregroundStyle(.white)
                            }
                        }
                        // Comment
                        Button(action: onComment) {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right").font(.title2).foregroundStyle(.white)
                                Text("\(post.comments ?? 0)").font(.caption).foregroundStyle(.white)
                            }
                        }
                        // Mute
                        Button {
                            isMuted.toggle(); player?.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3).foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 56)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
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
        endObserver = nil; player = nil
    }
}
