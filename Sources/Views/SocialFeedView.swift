import SwiftUI
import PhotosUI
import AVKit
import UIKit
import UniformTypeIdentifiers

// ======================== Bảng tin mạng xã hội (đăng tin · ảnh · video) ========================
struct SocialFeedView: View {
    @EnvironmentObject var store: AppStore
    var onOpenProfile: ((Int) -> Void)? = nil

    @State private var posts: [PostItem] = []
    @State private var loading = false
    @State private var error: String?

    // Soạn bài
    @State private var caption = ""
    @State private var picker: PhotosPickerItem?
    @State private var attachImage: UIImage?
    @State private var attachVideoURL: URL?
    @State private var attachKind: String?   // "image" | "video"
    @State private var posting = false

    @State private var commentsFor: PostIDWrapper?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                composer
                if loading && posts.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 30)
                } else if posts.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.bubble").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text(store.t("Chưa có bài viết. Hãy đăng bài đầu tiên!", "No posts yet. Be the first!"))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.top, 30)
                }
                ForEach(posts) { p in
                    SocialPostCard(post: p,
                                   onLike: { Task { await like(p) } },
                                   onComment: { commentsFor = PostIDWrapper(id: p.id) },
                                   onSave: { Task { await save(p) } },
                                   onProfile: { if let uid = p.userId { onOpenProfile?(uid) } })
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(12)
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $commentsFor) { w in PostCommentsView(postId: w.id).environmentObject(store) }
        .onChange(of: picker) { item in Task { await loadPicked(item) } }
    }

    // MARK: - Soạn bài
    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(store.t("Bạn đang nghĩ gì?", "What's on your mind?"), text: $caption, axis: .vertical)
                .lineLimit(1...5)
            if let img = attachImage {
                Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) { clearAttachButton }
            } else if attachKind == "video" {
                HStack {
                    Image(systemName: "film.fill").foregroundStyle(.blue)
                    Text(store.t("Đã chọn 1 video", "1 video selected")).font(.caption)
                    Spacer(); clearAttachButton
                }
                .padding(8).background(Color(.tertiarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 14) {
                PhotosPicker(selection: $picker, matching: .any(of: [.images, .videos])) {
                    Label(store.t("Ảnh / Video", "Photo / Video"), systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                }
                Spacer()
                Button { Task { await submit() } } label: {
                    if posting { ProgressView() }
                    else { Text(store.t("Đăng", "Post")).font(.subheadline.bold()) }
                }
                .disabled(posting || (caption.trimmingCharacters(in: .whitespaces).isEmpty && attachKind == nil))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var clearAttachButton: some View {
        Button {
            attachImage = nil; attachVideoURL = nil; attachKind = nil; picker = nil
        } label: {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.5)).padding(6)
        }
    }

    // MARK: - Hành động
    private func load() async {
        loading = true; error = nil
        do { posts = try await store.api.getSocialFeed() }
        catch { self.error = error.localizedDescription }
        loading = false
    }

    private func loadPicked(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        attachImage = nil; attachVideoURL = nil; attachKind = nil
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            if let movie = try? await item.loadTransferable(type: EditMovie.self) {
                attachVideoURL = movie.url; attachKind = "video"
            }
        } else if let data = try? await item.loadTransferable(type: Data.self),
                  let img = UIImage(data: data) {
            attachImage = img; attachKind = "image"
        }
    }

    private func submit() async {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && attachKind == nil { return }
        posting = true; error = nil
        do {
            var fileId = 0
            if attachKind == "video", let url = attachVideoURL {
                // Video → đăng kèm, hiển thị ở Reels
                let up = try await store.api.uploadFileRaw(
                    name: "v_\(Int(Date().timeIntervalSince1970)).mp4", category: "media", fileURL: url)
                fileId = up.id
            } else if attachKind == "image", let img = attachImage,
                      let data = img.jpegData(compressionQuality: 0.85) {
                fileId = try await store.api.mediaUploadId(
                    dataBase64: data.base64EncodedString(), mime: "image/jpeg",
                    name: "i_\(Int(Date().timeIntervalSince1970)).jpg")
            }
            _ = try await store.api.createPost(fileId: fileId, caption: text)
            caption = ""; attachImage = nil; attachVideoURL = nil; attachKind = nil; picker = nil
            await load()
        } catch { self.error = error.localizedDescription }
        posting = false
    }

    private func like(_ p: PostItem) async {
        do {
            let r = try await store.api.likePost(p.id)
            if let i = posts.firstIndex(where: { $0.id == p.id }) {
                posts[i].likes = r.likes; posts[i].liked = r.liked
            }
        } catch { self.error = error.localizedDescription }
    }

    private func save(_ p: PostItem) async {
        do {
            let r = try await store.api.savePost(p.id)
            if let i = posts.firstIndex(where: { $0.id == p.id }) { posts[i].saved = r.saved }
        } catch { self.error = error.localizedDescription }
    }
}

// ======================== Thẻ bài viết ========================
struct SocialPostCard: View {
    @EnvironmentObject var store: AppStore
    let post: PostItem
    var onLike: () -> Void
    var onComment: () -> Void
    var onSave: () -> Void = {}
    var onProfile: () -> Void = {}
    @State private var showFullImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onProfile) {
                HStack(spacing: 10) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(post.username).font(.subheadline.bold()).foregroundStyle(.primary)
                        Text(socialTimeAgo(post.createdAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }.buttonStyle(.plain)

            if let cap = post.caption, !cap.isEmpty {
                Text(cap).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            if post.kind == "image", let url = store.api.mediaURL(fileId: post.fileId) {
                Button { showFullImage = true } label: {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        Color(.tertiarySystemBackground).frame(height: 200)
                    }
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showFullImage) {
                    FullImageViewer(url: url)
                }
            }

            HStack(spacing: 22) {
                Button(action: onLike) {
                    Label("\(post.likes)", systemImage: post.liked ? "heart.fill" : "heart")
                        .foregroundStyle(post.liked ? .red : .secondary)
                }
                Button(action: onComment) {
                    Label("\(post.comments ?? 0)", systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                Button(action: onSave) {
                    Image(systemName: (post.saved ?? false) ? "bookmark.fill" : "bookmark")
                        .foregroundStyle((post.saved ?? false) ? .yellow : .secondary)
                }
                Spacer()
            }
            .font(.subheadline)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder private var avatar: some View {
        let initial = String(post.username.prefix(1)).uppercased()
        if let s = post.avatarUrl, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { img in img.resizable().scaledToFill() }
            placeholder: { Circle().fill(store.accentColor.opacity(0.5)).overlay(Text(initial).foregroundStyle(.white)) }
                .frame(width: 40, height: 40).clipShape(Circle())
        } else {
            Circle().fill(store.accentColor.opacity(0.5)).frame(width: 40, height: 40)
                .overlay(Text(initial).font(.headline).foregroundStyle(.white))
        }
    }
}

// ======================== Xem ảnh phóng to (zoom + kéo) ========================
struct FullImageViewer: View {
    let url: URL
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { img in
                img.resizable().scaledToFit()
            } placeholder: { ProgressView().tint(.white) }
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { v in scale = max(1, lastScale * v) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation { offset = .zero; lastOffset = .zero } }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in
                        if scale > 1 {
                            offset = CGSize(width: lastOffset.width + v.translation.width,
                                            height: lastOffset.height + v.translation.height)
                        }
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                    else { scale = 2.5; lastScale = 2.5 }
                }
            }
            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle).foregroundStyle(.white.opacity(0.9))
                    }.padding()
                }
                Spacer()
            }
        }
    }
}

// Thời gian tương đối ngắn gọn cho bài viết
func socialTimeAgo(_ at: Int?) -> String {
    guard let at, at > 0 else { return "" }
    let s = max(0, Int(Date().timeIntervalSince1970) - at)
    if s < 60 { return "Vừa xong" }
    if s < 3600 { return "\(s/60) phút trước" }
    if s < 86400 { return "\(s/3600) giờ trước" }
    return "\(s/86400) ngày trước"
}
