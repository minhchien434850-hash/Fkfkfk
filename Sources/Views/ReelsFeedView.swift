import SwiftUI
import AVKit
import PhotosUI
import UIKit


// ======================== Reels — fullscreen cuộn dọc ========================
struct ReelsFeedView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var currentIndex = 0
    @State private var dragOffset: CGFloat = 0
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
                    let h = geo.size.height
                    let lo = max(0, currentIndex - 1)
                    let hi = min(posts.count - 1, currentIndex + 1)
                    // Pager dọc: vuốt LÊN = video kế tiếp, vuốt XUỐNG = xem lại video trước.
                    // Chỉ render 3 video quanh vị trí hiện tại cho nhẹ máy.
                    ZStack {
                        ForEach(Array(lo...hi), id: \.self) { idx in
                            let p = posts[idx]
                            ReelCard(post: p, token: store.token, baseURL: store.baseURL,
                                     isActive: currentIndex == idx,
                                     currentUserId: store.userId,
                                     onLike: { Task { await like(p) } },
                                     onComment: { commentsFor = PostIDWrapper(id: p.id) },
                                     onFollow: { Task { await toggleFollow(p) } })
                                .frame(width: geo.size.width, height: h)
                                .offset(y: CGFloat(idx - currentIndex) * h + dragOffset)
                        }
                    }
                    .frame(width: geo.size.width, height: h)
                    .animation(.spring(response: 0.35, dampingFraction: 0.86), value: currentIndex)
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                var t = v.translation.height
                                // Cản tay khi đã ở đầu/cuối (kéo vào khoảng trống)
                                if (currentIndex == 0 && t > 0) || (currentIndex == posts.count - 1 && t < 0) {
                                    t *= 0.3
                                }
                                dragOffset = t
                            }
                            .onEnded { v in
                                let move = v.predictedEndTranslation.height
                                let threshold = h * 0.18
                                var idx = currentIndex
                                if move < -threshold && currentIndex < posts.count - 1 {
                                    idx += 1                       // vuốt lên → video kế tiếp
                                } else if move > threshold && currentIndex > 0 {
                                    idx -= 1                       // vuốt xuống → video vừa lướt qua
                                }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                    currentIndex = idx
                                    dragOffset = 0
                                }
                            }
                    )
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

    private func toggleFollow(_ p: PostItem) async {
        guard let uid = p.userId else { return }
        let nowFollowing = !(p.following ?? false)
        do {
            if nowFollowing { _ = try await store.api.follow(uid) }
            else { _ = try await store.api.unfollow(uid) }
            // Cập nhật mọi video của cùng tác giả để nút Theo dõi đồng bộ
            for i in posts.indices where posts[i].userId == uid {
                posts[i].following = nowFollowing
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
    var currentUserId: Int? = nil
    var onLike: () -> Void
    var onComment: () -> Void
    var onFollow: () -> Void = {}

    @State private var player: AVPlayer?
    @State private var thumb: UIImage?
    @State private var isMuted = false
    @State private var showLikeBurst = false
    @State private var endObserver: NSObjectProtocol?

    private var streamURL: URL? { keniosVideoURL(postId: post.id, token: token, baseURL: baseURL) }
    private var isMine: Bool { currentUserId != nil && post.userId == currentUserId }

    @ViewBuilder private var avatarCircle: some View {
        let initial = String(post.username.prefix(1)).uppercased()
        if let s = post.avatarUrl, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Theme.accent.opacity(0.6)).overlay(Text(initial).font(.headline).foregroundStyle(.white))
            }
            .frame(width: 44, height: 44).clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
        } else {
            Circle().fill(Theme.accent.opacity(0.6))
                .frame(width: 44, height: 44)
                .overlay(Text(initial).font(.headline).foregroundStyle(.white))
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }
    private var shareText: String {
        let who = post.username.isEmpty ? "KENIOS" : post.username
        let cap = (post.caption?.isEmpty == false) ? " – \(post.caption!)" : ""
        return "Xem video của \(who) trên KENIOS\(cap)"
    }

    var body: some View {
        ZStack {
            // Nền mờ phủ kín để không bị viền đen xấu, video chính fit ở trên (không phóng to/thu nhỏ).
            Color.black.ignoresSafeArea()
            if let thumb {
                Image(uiImage: thumb).resizable().scaledToFill()
                    .ignoresSafeArea().blur(radius: 24).opacity(0.5)
                Image(uiImage: thumb).resizable().scaledToFit().ignoresSafeArea()
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
                    VStack(spacing: 20) {
                        // Avatar + nút Theo dõi (ẩn nếu là video của chính mình)
                        if !isMine {
                            Button(action: onFollow) {
                                ZStack(alignment: .bottom) {
                                    avatarCircle
                                    Image(systemName: (post.following ?? false) ? "checkmark.circle.fill" : "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle((post.following ?? false) ? .green : .red)
                                        .background(Circle().fill(.white))
                                        .offset(y: 9)
                                }
                                .frame(height: 52)
                            }
                        }
                        // Tim
                        Button(action: onLike) {
                            VStack(spacing: 4) {
                                Image(systemName: post.liked ? "heart.fill" : "heart")
                                    .font(.title2).foregroundStyle(post.liked ? .red : .white)
                                Text("\(post.likes)").font(.caption).foregroundStyle(.white)
                            }
                        }
                        // Bình luận
                        Button(action: onComment) {
                            VStack(spacing: 4) {
                                Image(systemName: "bubble.right.fill").font(.title2).foregroundStyle(.white)
                                Text("\(post.comments ?? 0)").font(.caption).foregroundStyle(.white)
                            }
                        }
                        // Chia sẻ
                        ShareLink(item: shareText) {
                            VStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.right.fill").font(.title2).foregroundStyle(.white)
                                Text("Chia sẻ").font(.caption).foregroundStyle(.white)
                            }
                        }
                        // Tắt/bật tiếng
                        Button {
                            isMuted.toggle(); player?.isMuted = isMuted
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.title3).foregroundStyle(.white)
                        }
                    }
                    .shadow(color: .black.opacity(0.4), radius: 3)
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
        .onAppear { loadThumb(); if isActive { setupPlayer() } }
        .onDisappear { teardown() }
        .onChange(of: isActive) { active in
            // Chỉ video đang xem mới tạo & phát player; rời đi thì giải phóng cho nhẹ máy
            if active {
                if player == nil { setupPlayer() }
                player?.seek(to: .zero); player?.play()
            } else {
                teardown()
            }
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
