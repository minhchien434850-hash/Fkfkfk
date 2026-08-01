import SwiftUI
import AVKit
import PhotosUI
import UIKit


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
    @State private var showReels = false
    @State private var reelsIndex = 0

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
                            ForEach(Array(posts.enumerated()), id: \.element.id) { idx, p in
                                Button { reelsIndex = idx; showReels = true } label: {
                                    VideoGridCell(post: p, token: store.token, baseURL: store.baseURL)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 12)
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
        .fullScreenCover(isPresented: $showReels) {
            ReelsFeedView(presetPosts: posts, startIndex: reelsIndex).environmentObject(store)
        }
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
            // Dùng /media/upload → trả link ảnh CÔNG KHAI (/media/{id}) phục vụ inline,
            // tải được bằng AsyncImage (không cần token) và người khác cũng xem được.
            let avatarUrl = try await store.api.mediaUpload(
                dataBase64: data.base64EncodedString(), mime: "image/jpeg", name: "avatar.jpg")
            _ = try await store.api.updateProfile(publicId: nil, avatarUrl: avatarUrl, bio: nil)
            await load()
        } catch { self.error = error.localizedDescription }
        uploadingAvatar = false
    }
}
