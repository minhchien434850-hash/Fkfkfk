import SwiftUI
import AVKit
import PhotosUI
import UIKit


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
                // Giữ NGUYÊN tỉ lệ video (ngang ra ngang, dọc ra dọc), không cắt
                AspectVideoPlayer(player: player)
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
        let who = post.username.isEmpty ? "KENIOS" : post.username
        let cap = (post.caption?.isEmpty == false) ? " – \(post.caption!)" : ""
        var items: [Any] = ["Xem video của \(who) trên KENIOS\(cap)"]
        if let url = keniosVideoURL(postId: post.id, token: nil, baseURL: store.baseURL) {
            items.append(url)
        }
        keniosPresentShare(items)
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
                    Toggle(store.t("Công khai (hiện trên Reels)", "Public (visible in Reels)"),
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
            // Nén H.264 720p trước khi tải lên → tải nhanh hơn nhiều & phát mượt.
            let upURL = await VideoUploadHelper.compressForUpload(movie.url)
            let up = try await store.api.uploadFileRaw(
                name: "video_\(Int(Date().timeIntervalSince1970)).mp4",
                category: "video", fileURL: upURL)
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
