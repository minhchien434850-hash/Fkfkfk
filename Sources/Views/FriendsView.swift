import SwiftUI
import PhotosUI

struct FriendsView: View {
    @EnvironmentObject var store: AppStore

    // §4.2 — Đổi ảnh đại diện ngay trong khu nhắn tin
    @State private var myAvatar = ""
    @State private var avatarItem: PhotosPickerItem?
    @State private var uploadingAvatar = false

    @State private var selectedSegment = 0 // 0: Bạn bè, 1: Lời mời, 2: Tìm kiếm
    @State private var searchQuery = ""
    @State private var searchResults: [UserSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String? = nil
    
    @State private var loadingRequests = false
    @State private var loadingFriends = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Banner sang trọng
                KHeroHeader(icon: "person.2.fill",
                            title: store.t("Bạn bè", "Friends"),
                            subtitle: store.t("Kết bạn · Lời mời · Nhắn tin trực tiếp",
                                              "Add friends · Requests · Direct messages"))
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Segmented picker
                Picker("", selection: $selectedSegment) {
                    Text(store.t("Bạn bè", "Friends")).tag(0)
                    Text(store.t("Lời mời", "Requests")).tag(1)
                    Text(store.t("Tìm kiếm", "Search")).tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)

                myAvatarRow

                Group {
                    if selectedSegment == 0 {
                        friendsPane
                    } else if selectedSegment == 1 {
                        requestsPane
                    } else {
                        searchPane
                    }
                }
                
                Spacer()
            }
            .navigationTitle(store.t("Bạn bè", "Friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThreeDLogoText(size: 20)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await refreshData()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await refreshData()
                await loadMyAvatar()
            }
            .onChange(of: avatarItem) { item in
                guard let item else { return }
                Task { await uploadAvatar(item) }
            }
        }
    }

    // MARK: - §4.2 Đổi ảnh đại diện trong khu nhắn tin
    private var myAvatarRow: some View {
        HStack(spacing: 12) {
            ZStack {
                if let url = URL(string: myAvatar), !myAvatar.isEmpty {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemBackground)
                    }
                    .frame(width: 52, height: 52).clipShape(Circle())
                } else {
                    Circle().fill(Theme.accent.opacity(0.15)).frame(width: 52, height: 52)
                        .overlay(Image(systemName: "person.fill").foregroundStyle(Theme.accent))
                }
                if uploadingAvatar {
                    Circle().fill(.black.opacity(0.4)).frame(width: 52, height: 52)
                    ProgressView().tint(.white)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.t("Ảnh đại diện của bạn", "Your avatar")).font(.subheadline.bold())
                Text(store.t("Bạn bè sẽ thấy ảnh mới khi làm mới trò chuyện.",
                             "Friends see the new photo when the chat refreshes."))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            PhotosPicker(selection: $avatarItem, matching: .images) {
                Label(store.t("Đổi ảnh", "Change"), systemImage: "camera.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.15)).clipShape(Capsule())
            }
            .disabled(uploadingAvatar)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private func loadMyAvatar() async {
        if let p = try? await store.api.myProfile() {
            myAvatar = p.avatarUrl ?? ""
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploadingAvatar = true
        defer { uploadingAvatar = false; avatarItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { return }
        do {
            let url = try await store.api.mediaUpload(
                dataBase64: data.base64EncodedString(), mime: "image/jpeg",
                name: "avatar_\(Int(Date().timeIntervalSince1970)).jpg")
            _ = try await store.api.updateProfile(publicId: nil, avatarUrl: url, bio: nil)
            myAvatar = url
        } catch {
            // Lỗi mạng/tải lên — giữ ảnh cũ, người dùng thử lại.
        }
    }

    // MARK: - Friends Pane
    private var friendsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loadingFriends {
                    HStack {
                        Spacer()
                        ProgressView(store.t("Đang tải danh sách...", "Loading list..."))
                        Spacer()
                    }
                    .padding(.top, 40)
                } else if store.friends.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.2.slash.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text(store.t("Chưa có bạn bè", "No friends yet"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text(store.t("Hãy qua tab 'Tìm kiếm' để kết bạn với những người khác!",
                                     "Go to the 'Search' tab to add other people!"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(store.friends) { friend in
                        NavigationLink(destination: DirectMessageChatView(friend: friend)) {
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title)
                                    .foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(friend.username)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(store.t("Bấm để nhắn tin", "Tap to message"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .kGlassInteractive(RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Requests Pane
    private var requestsPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loadingRequests {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                } else {
                    let username = store.username ?? ""
                    let incomingRequests = store.friendRequests.filter { $0.receiverName.lowercased() == username.lowercased() }
                    let outgoingRequests = store.friendRequests.filter { $0.senderName.lowercased() == username.lowercased() }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Lời mời nhận được", "Received requests") + " (\(incomingRequests.count))")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)

                        if incomingRequests.isEmpty {
                            Text(store.t("Không có lời mời nào", "No requests"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .kGlass(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        } else {
                            ForEach(incomingRequests) { req in
                                HStack {
                                    Image(systemName: "person.badge.plus")
                                        .font(.headline)
                                        .foregroundStyle(Theme.purple)
                                    Text(req.senderName)
                                        .font(.headline)
                                    Spacer()
                                    Button(store.t("Từ chối", "Decline")) {
                                        Task { await respond(reqId: req.id, action: "decline") }
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.systemGray5))
                                    .cornerRadius(8)
                                    
                                    Button(store.t("Đồng ý", "Accept")) {
                                        Task { await respond(reqId: req.id, action: "accept") }
                                    }
                                    .font(.caption)
                                    .bold()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent)
                                    .cornerRadius(8)
                                }
                                .padding()
                                .kGlass(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    // Outgoing requests
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.t("Yêu cầu đã gửi", "Sent requests") + " (\(outgoingRequests.count))")
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 10)

                        if outgoingRequests.isEmpty {
                            Text(store.t("Không có yêu cầu đang chờ", "No pending requests"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .kGlass(RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal)
                        } else {
                            ForEach(outgoingRequests) { req in
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(req.receiverName)
                                        .font(.body)
                                    Spacer()
                                    Text(store.t("Đang chờ phản hồi", "Awaiting response"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .kGlass(RoundedRectangle(cornerRadius: 16))
                                .padding(.horizontal)
                            }
                        }
                    }
                }
            }
            .padding(.vertical)
        }
    }
    
    // MARK: - Search Pane
    private var searchPane: some View {
        VStack(spacing: 12) {
            // ID của bạn để người khác kết bạn
            HStack {
                Image(systemName: "qrcode").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.t("ID của bạn", "Your ID")).font(.caption2).foregroundStyle(.secondary)
                    Text(store.publicId.isEmpty ? "—" : store.publicId)
                        .font(.subheadline.bold()).foregroundStyle(Theme.accent)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = store.publicId
                } label: { Image(systemName: "doc.on.doc") }
            }
            .padding(12).kCard(12).padding(.horizontal)

            // Search Input
            HStack {
                TextField(store.t("Nhập tên · SĐT · ID (KEN...)", "Enter name · phone · ID (KEN...)"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if isSearching {
                    ProgressView()
                } else {
                    Button {
                        Task { await runSearch() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .bold()
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(12)
            .kGlass(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            
            if let err = searchError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            ScrollView {
                VStack(spacing: 12) {
                    if searchResults.isEmpty && !searchQuery.isEmpty && !isSearching {
                        Text(store.t("Không tìm thấy kết quả phù hợp", "No matching results"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(searchResults) { res in
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(res.username).font(.headline)
                                    if let pid = res.publicId, !pid.isEmpty {
                                        Text("ID: \(pid)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                
                                searchResultActionView(for: res)
                            }
                            .padding()
                            .kGlass(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
        }
        .padding(.vertical)
    }
    
    @ViewBuilder
    private func searchResultActionView(for user: UserSearchResult) -> some View {
        let isFriend = store.friends.contains { $0.id == user.id }
        let incomingRequest = store.friendRequests.first { $0.senderName.lowercased() == user.username.lowercased() }
        let outgoingRequest = store.friendRequests.first { $0.receiverName.lowercased() == user.username.lowercased() }
        
        if isFriend {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(store.t("Bạn bè", "Friends")).font(.caption).foregroundStyle(.secondary)
            }
        } else if let incReq = incomingRequest {
            Button(store.t("Chấp nhận", "Accept")) {
                Task { await respond(reqId: incReq.id, action: "accept") }
            }
            .font(.caption)
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accent)
            .cornerRadius(8)
        } else if outgoingRequest != nil {
            Text(store.t("Đã gửi lời mời", "Request sent"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Button(store.t("Thêm bạn", "Add friend")) {
                Task { await sendRequest(friendId: user.id) }
            }
            .font(.caption)
            .bold()
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.accent)
            .cornerRadius(8)
        }
    }
    
    // MARK: - Helpers & API calls
    private func refreshData() async {
        loadingFriends = true
        loadingRequests = true
        await store.refreshFriends()
        loadingFriends = false
        await store.refreshFriendRequests()
        loadingRequests = false
    }
    
    private func runSearch() async {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchError = nil
        do {
            searchResults = try await store.api.searchUsers(query: searchQuery)
        } catch {
            searchError = error.localizedDescription
        }
        isSearching = false
    }
    
    private func sendRequest(friendId: Int) async {
        do {
            _ = try await store.api.sendFriendRequest(friendId: friendId)
            await refreshData()
        } catch {
            searchError = error.localizedDescription
        }
    }
    
    private func respond(reqId: Int, action: String) async {
        do {
            _ = try await store.api.respondToFriendRequest(requestId: reqId, action: action)
            await refreshData()
        } catch {
            searchError = error.localizedDescription
        }
    }
}
