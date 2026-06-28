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
    @State private var selectedTab = 0   // 0=Của tôi, 1=Reels (fullscreen)
    @State private var profileSheet: ProfileIDWrapper?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text(store.t("Của tôi", "My Videos")).tag(0)
                    Text("Reels").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                MyVideosView()
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
            get: { selectedTab == 1 },
            set: { if !$0 { selectedTab = 0 } }
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
