import SwiftUI
import UniformTypeIdentifiers


struct GitHubView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("github_token") private var token = ""
    @State private var user: GHUser?
    @State private var repos: [GHRepo] = []
    @State private var loading = false
    @State private var error: String?

    // login fields
    @State private var tokenInput = ""
    @State private var showTokenBrowser = false

    // create repo
    @State private var showCreate = false
    @State private var newRepoName = ""
    @State private var newRepoPrivate = true

    var body: some View {
        NavigationStack {
            Group {
                if !store.isPro {
                    ProLockCard(feature: "Liên kết GitHub")
                } else if user == nil {
                    loginView
                } else {
                    repoListView
                }
            }
            .navigationTitle("GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if !token.isEmpty && user == nil { await validate(token) }
            }
            .sheet(isPresented: $showTokenBrowser) {
                NavigationStack {
                    TokenBrowser()
                        .navigationTitle(store.t("Tạo Token GitHub", "Create GitHub Token"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) {
                            Button(store.t("Xong", "Done")) { showTokenBrowser = false }
                        } }
                }
            }
        }
    }

    // MARK: - Đăng nhập
    private var loginView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                KHeroHeader(icon: "chevron.left.forwardslash.chevron.right",
                            title: "GitHub",
                            subtitle: store.t("Đăng nhập để tải file / mã nguồn lên repo của bạn",
                                              "Sign in to upload files / source code to your repo"))

                VStack(alignment: .leading, spacing: 10) {
                    Text(store.t("Cách đăng nhập", "How to sign in")).font(.headline)
                    Label(store.t("Bấm \"Mở GitHub & tạo token\" — đăng nhập tài khoản GitHub ngay trong app.", "Tap \"Open GitHub & create token\" — sign in to GitHub right in the app."), systemImage: "1.circle.fill")
                    Label(store.t("Ở trang token, chọn quyền \"repo\" rồi bấm Generate, copy token.", "On the token page, pick the \"repo\" scope, tap Generate, copy the token."), systemImage: "2.circle.fill")
                    Label(store.t("Quay lại đây, dán token vào ô dưới và bấm Đăng nhập.", "Return here, paste the token below and tap Login."), systemImage: "3.circle.fill")
                }
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .kCard(16)

                Button {
                    showTokenBrowser = true
                } label: {
                    Label(store.t("Mở GitHub & tạo token", "Open GitHub & create token"), systemImage: "safari.fill")
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Theme.accent).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal Access Token").font(.caption).foregroundStyle(.secondary)
                    SecureField("ghp_xxxxxxxx hoặc github_pat_xxxx", text: $tokenInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(12).kCard(12)
                }

                Button {
                    Task { await validate(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)) }
                } label: {
                    HStack {
                        if loading { ProgressView().tint(.white) }
                        Text(loading ? "Đang kiểm tra..." : "Đăng nhập")
                    }
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(tokenInput.isEmpty || loading ? Color.gray : Theme.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(tokenInput.isEmpty || loading)

                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .padding()
        }
    }

    // MARK: - Danh sách repo
    private var repoListView: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: user?.avatar_url ?? "")) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill").resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user?.name ?? user?.login ?? "—").font(.headline)
                        Text("@\(user?.login ?? "")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(store.t("Đăng xuất", "Logout"), role: .destructive) { logout() }
                        .font(.caption)
                }
            }

            Section {
                Button {
                    newRepoName = ""; newRepoPrivate = true; showCreate = true
                } label: {
                    Label(store.t("Tạo repo mới", "Create new repo"), systemImage: "plus.circle.fill")
                }
            }

            Section(store.t("Repo của bạn", "Your repos") + " (\(repos.count))") {
                if loading && repos.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(repos) { repo in
                    NavigationLink {
                        GitHubRepoView(api: GitHubAPI(token: token), repo: repo)
                    } label: {
                        HStack {
                            Image(systemName: repo.`private` ? "lock.fill" : "book.closed.fill")
                                .foregroundStyle(repo.`private` ? Theme.gold : Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name).font(.subheadline.bold())
                                Text(repo.full_name).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let error { Text(error).foregroundStyle(.red).font(.caption) }
        }
        .refreshable { await loadRepos() }
        .alert("Tạo repo mới", isPresented: $showCreate) {
            TextField(store.t("Tên repo (vd: my-app)", "Repo name (e.g. my-app)"), text: $newRepoName)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(store.t("Tạo", "Create")) { Task { await createRepo() } }
            Button(store.t("Huỷ", "Cancel"), role: .cancel) { }
        } message: {
            Text(store.t("Repo sẽ ở chế độ riêng tư. Bạn có thể tải file lên ngay sau khi tạo.",
                         "The repo will be private. You can upload files right after creating it."))
        }
    }

    // MARK: - Actions
    private func validate(_ tk: String) async {
        guard !tk.isEmpty else { return }
        loading = true; error = nil
        do {
            let api = GitHubAPI(token: tk)
            let u = try await api.me()
            token = tk; tokenInput = ""
            user = u
            await loadRepos()
        } catch {
            self.error = error.localizedDescription
            user = nil
        }
        loading = false
    }
    private func loadRepos() async {
        guard !token.isEmpty else { return }
        loading = true
        do { repos = try await GitHubAPI(token: token).repos() }
        catch { self.error = error.localizedDescription }
        loading = false
    }
    private func createRepo() async {
        let name = newRepoName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        loading = true; error = nil
        let api = GitHubAPI(token: token)
        do {
            // Dùng repo trả về trực tiếp để không phụ thuộc vào độ trễ đồng bộ của GitHub
            let repo = try await api.createRepo(name: name, isPrivate: newRepoPrivate)
            if !repos.contains(where: { $0.id == repo.id }) { repos.insert(repo, at: 0) }
            await loadRepos()
        } catch let e as GitHubError {
            // Nếu repo đã tồn tại → mở repo đó thay vì báo lỗi (tránh kẹt "không tạo được repo")
            if case .http(422, let msg) = e, msg.lowercased().contains("already exists"),
               let owner = user?.login,
               let existing = try? await api.getRepo(owner: owner, name: name) {
                if !repos.contains(where: { $0.id == existing.id }) { repos.insert(existing, at: 0) }
                error = "Repo \"\(name)\" đã có sẵn — đã mở trong danh sách bên dưới."
            } else {
                error = e.localizedDescription
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
    private func logout() {
        token = ""; user = nil; repos = []; error = nil
    }
}

// MARK: - Màn hình repo: tải file lên
struct GitHubRepoView: View {
    @EnvironmentObject var store: AppStore
    let api: GitHubAPI
    let repo: GHRepo

    @State private var folder = ""
    @State private var showImporter = false
    @State private var uploading = false
    @State private var log: [String] = []
    @State private var error: String?

    // Duyệt & xoá file
    @State private var contents: [GHContent] = []
    @State private var loadingList = false

    // Build app (Actions)
    @State private var runs: [GHRun] = []
    @State private var building = false
    @State private var buildMsg: String?
    @State private var ipaURL: String?
    @State private var releasePage: String?

    private var branch: String { repo.default_branch ?? "main" }

    var body: some View {
        Form {
            Section(store.t("Đích tải lên", "Upload destination")) {
                LabeledContent("Repo", value: repo.full_name)
                LabeledContent(store.t("Nhánh", "Branch"), value: branch)
                TextField(store.t("Thư mục (để trống = gốc repo)", "Folder (empty = repo root)"), text: $folder)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    HStack {
                        if uploading { ProgressView().padding(.trailing, 4) }
                        Label(uploading ? store.t("Đang tải lên...", "Uploading...") : store.t("Chọn file để tải lên", "Choose files to upload"),
                              systemImage: "arrow.up.doc.fill")
                    }
                }
                .disabled(uploading)
            } footer: {
                Text(store.t("Chọn 1 hoặc nhiều file (ảnh, mã nguồn, tài liệu...). File sẽ được commit thẳng vào repo qua GitHub API.",
                             "Pick one or more files (images, source, documents...). They commit straight to the repo via GitHub API."))
            }

            if !log.isEmpty {
                Section(store.t("Kết quả", "Result")) {
                    ForEach(log, id: \.self) { line in
                        Text(line).font(.caption).foregroundStyle(line.contains("✓") ? .green : .red)
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            // Duyệt & xoá file trong thư mục hiện tại
            Section {
                Button {
                    Task { await loadList() }
                } label: {
                    HStack {
                        if loadingList { ProgressView().padding(.trailing, 4) }
                        Label("Xem file trong thư mục này", systemImage: "folder")
                    }
                }.disabled(loadingList)

                ForEach(contents) { item in
                    HStack {
                        Image(systemName: item.type == "dir" ? "folder.fill" : "doc.fill")
                            .foregroundStyle(item.type == "dir" ? Theme.gold : Theme.accent)
                        Text(item.name).lineLimit(1)
                        Spacer()
                        if item.type == "file" {
                            Button(role: .destructive) {
                                Task { await deleteFile(item) }
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } header: { Text("File trong repo") }
            footer: { Text("Bấm thùng rác để xoá file khỏi repo (commit xoá luôn trên GitHub).") }

            // ====== Build app IPA qua GitHub Actions ======
            Section {
                Button {
                    Task { await build() }
                } label: {
                    HStack {
                        if building { ProgressView().padding(.trailing, 4) }
                        Label(building ? "Đang gửi lệnh build..." : "Build app IPA (chạy trên GitHub)",
                              systemImage: "hammer.fill")
                    }
                }.disabled(building)

                Button { Task { await loadRuns() } } label: {
                    Label("Làm mới trạng thái build", systemImage: "arrow.clockwise")
                }
                ForEach(runs) { r in
                    HStack {
                        Image(systemName: runIcon(r)).foregroundStyle(runColor(r))
                        Text("Run #\(r.run_number ?? r.id)").font(.caption)
                        Spacer()
                        Text(runText(r)).font(.caption2).foregroundStyle(.secondary)
                        if let u = r.html_url, let url = URL(string: u) {
                            Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                        }
                    }
                }
                if let ipaURL, let url = URL(string: ipaURL) {
                    Link(destination: url) {
                        Label("Tải IPA mới nhất", systemImage: "square.and.arrow.down")
                            .foregroundStyle(.green)
                    }
                } else if let releasePage, let url = URL(string: releasePage) {
                    Link(destination: url) {
                        Label("Mở bản phát hành (Releases)", systemImage: "shippingbox")
                    }
                }
                if let buildMsg { Text(buildMsg).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Build app (GitHub Actions)") }
            footer: {
                Text("Build chạy trên máy chủ của GitHub (không phải điện thoại). Cần repo có file .github/workflows/build-app.yml và token quyền 'workflow'. Xong vào Releases tải KENIOS.ipa.")
            }

            Section {
                if let urlStr = repo.html_url, let url = URL(string: urlStr) {
                    Link(destination: url) {
                        Label("Mở repo trên GitHub", systemImage: "safari")
                    }
                }
            }
        }
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRuns(); await loadRelease() }
        .sheet(isPresented: $showImporter) {
            DocumentPicker(allowsMultipleSelection: true, asCopy: true) { urls in
                Task { await upload(urls) }
            }
            .ignoresSafeArea()
        }
    }

    private func build() async {
        building = true; buildMsg = nil
        do {
            try await api.triggerBuild(fullName: repo.full_name, workflow: "build-app.yml", ref: branch)
            buildMsg = "Đã gửi lệnh build. Đợi vài phút rồi bấm 'Làm mới trạng thái'."
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await loadRuns()
        } catch let e as GitHubError {
            if case .http(404, _) = e {
                buildMsg = "Lỗi 404: Repo này chưa có file .github/workflows/build-app.yml hoặc token thiếu quyền 'workflow'. Hãy copy file workflow từ repo KENIOS gốc sang repo này rồi thử lại."
            } else {
                buildMsg = "Không gửi được lệnh build: \(e.localizedDescription)"
            }
        } catch {
            buildMsg = "Không gửi được lệnh build: \(error.localizedDescription)"
        }
        building = false
    }
    private func loadRuns() async {
        if let rs = try? await api.listRuns(fullName: repo.full_name) { runs = rs }
        await loadRelease()
    }
    private func loadRelease() async {
        if let rel = await api.latestRelease(fullName: repo.full_name) {
            releasePage = rel.html_url
            ipaURL = rel.assets.first(where: { $0.name.lowercased().hasSuffix(".ipa") })?.browser_download_url
        }
    }
    private func runIcon(_ r: GHRun) -> String {
        if r.status != "completed" { return "clock" }
        return r.conclusion == "success" ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    private func runColor(_ r: GHRun) -> Color {
        if r.status != "completed" { return .orange }
        return r.conclusion == "success" ? .green : .red
    }
    private func runText(_ r: GHRun) -> String {
        if r.status != "completed" { return r.status == "in_progress" ? "đang chạy" : "đang chờ" }
        return r.conclusion == "success" ? "thành công" : (r.conclusion ?? "lỗi")
    }

    private func loadList() async {
        loadingList = true; error = nil
        let dir = folder.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        do { contents = try await api.listContents(fullName: repo.full_name, path: dir, branch: branch) }
        catch { self.error = error.localizedDescription }
        loadingList = false
    }

    private func deleteFile(_ item: GHContent) async {
        error = nil
        do {
            try await api.deleteFile(fullName: repo.full_name, path: item.path,
                                     message: "Xoá \(item.name) từ KENIOS",
                                     branch: branch, sha: item.sha)
            contents.removeAll { $0.id == item.id }
            log.insert("✓ Đã xoá \(item.path)", at: 0)
        } catch { self.error = error.localizedDescription }
    }

    private func upload(_ urls: [URL]) async {
        uploading = true; error = nil; log = []
        let dir = folder.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        for url in urls {
            // Bắt buộc gọi startAccessingSecurityScopedResource trước khi đọc file
            let access = url.startAccessingSecurityScopedResource()
            let name = url.lastPathComponent
            let path = dir.isEmpty ? name : "\(dir)/\(name)"
            do {
                // Copy sang temp trước (tránh mất quyền trong async context)
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(name)
                try? FileManager.default.removeItem(at: tmp)
                try FileManager.default.copyItem(at: url, to: tmp)
                if access { url.stopAccessingSecurityScopedResource() }

                let data = try Data(contentsOf: tmp)
                let b64 = data.base64EncodedString()
                let sha = await api.existingSha(fullName: repo.full_name, path: path, branch: branch)
                try await api.uploadFile(fullName: repo.full_name, path: path,
                                         contentBase64: b64,
                                         message: "Tải lên \(name) từ KENIOS",
                                         branch: branch, sha: sha)
                log.append("✓ \(path) (\(humanSize(data.count)))")
                try? FileManager.default.removeItem(at: tmp)
            } catch {
                if access { url.stopAccessingSecurityScopedResource() }
                log.append("✗ \(name): \(error.localizedDescription)")
            }
        }
        uploading = false
    }
}

// Trình duyệt mở trang tạo token GitHub (đăng nhập ngay trong app)
struct TokenBrowser: View {
    @StateObject private var model = BrowserModel()
    var body: some View {
        BrowserWebView(model: model)
            .ignoresSafeArea(edges: .bottom)
            .onAppear { model.open("https://github.com/settings/tokens/new?scopes=repo&description=KENIOS") }
    }
}
