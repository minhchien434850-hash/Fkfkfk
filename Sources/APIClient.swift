import Foundation

enum APIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let m): return m }
    }
}

struct APIClient {
    let baseURL: String
    var token: String?

    private var root: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func makeURL(_ path: String) throws -> URL {
        guard let u = URL(string: root + path) else {
            throw APIError.message("URL máy chủ không hợp lệ.")
        }
        return u
    }

    private func send(_ path: String, method: String = "GET",
                      json: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = method
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json { req.httpBody = try JSONSerialization.data(withJSONObject: json) }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw APIError.message("Không kết nối được máy chủ. Kiểm tra IP/URL & mạng.")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("Phản hồi không hợp lệ.")
        }
        if !(200..<300).contains(http.statusCode) {
            var detail = "Lỗi máy chủ (\(http.statusCode))."
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = obj["detail"] as? String { detail = d }
            throw APIError.message(detail)
        }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    // ---- Hệ thống ----
    func getConfig() async throws -> ServerConfig {
        try decode(try await send("/config", auth: false))
    }
    func getProviders() async throws -> [Provider] {
        try decode(try await send("/providers", auth: false))
    }

    // ---- Tài khoản ----
    func register(_ username: String, _ password: String, email: String?, phone: String?,
                  code: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["username": username, "password": password]
        if let email, !email.isEmpty { body["email"] = email }
        if let phone, !phone.isEmpty { body["phone"] = phone }
        if let code, !code.isEmpty { body["code"] = code }
        return try decode(try await send("/auth/register", method: "POST", json: body, auth: false))
    }
    // ---- Chat streaming (trả lời hiện dần) ----
    /// Trả về conversationId. Mỗi đoạn text gọi onDelta trên main actor.
    @discardableResult
    func chatStream(provider: String, message: String, conversationId: Int?, model: String? = nil,
                    system: String? = nil, onDelta: @escaping (String) -> Void) async throws -> Int {
        var req = URLRequest(url: try makeURL("/chat/stream"))
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        var body: [String: Any] = ["provider": provider, "message": message]
        if let conversationId { body["conversation_id"] = conversationId }
        if let model { body["model"] = model }
        if let system { body["system"] = system }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.message("Phản hồi không hợp lệ.") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.message("Lỗi máy chủ (\(http.statusCode)).")
        }
        var convId = conversationId ?? 0
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, let d = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let delta = obj["delta"] as? String { onDelta(delta) }
            if let err = obj["error"] as? String { throw APIError.message(err) }
            if let cid = obj["conversation_id"] as? Int { convId = cid }
        }
        return convId
    }

    // Gửi mã xác nhận (OTP) qua email
    func sendOtp(email: String, purpose: String = "register") async throws -> OtpSendResponse {
        try decode(try await send("/auth/send-otp", method: "POST",
                                  json: ["email": email, "purpose": purpose], auth: false))
    }
    func login(_ username: String, _ password: String) async throws -> AuthResponse {
        try decode(try await send("/auth/login", method: "POST",
                                  json: ["username": username, "password": password], auth: false))
    }
    func forgot(_ username: String) async throws -> ForgotResponse {
        try decode(try await send("/auth/forgot-password", method: "POST",
                                  json: ["username": username], auth: false))
    }
    func reset(_ token: String, _ newPassword: String) async throws -> MessageResponse {
        try decode(try await send("/auth/reset-password", method: "POST",
                                  json: ["token": token, "new_password": newPassword], auth: false))
    }
    func updateProfile(email: String?, phone: String?, newPassword: String?) async throws -> MessageResponse {
        var body: [String: Any] = [:]
        if let email { body["email"] = email }
        if let phone { body["phone"] = phone }
        if let newPassword, !newPassword.isEmpty { body["new_password"] = newPassword }
        return try decode(try await send("/auth/update-profile", method: "POST", json: body))
    }

    // ---- API key (user) ----
    func saveKey(provider: String, apiKey: String) async throws -> MessageResponse {
        try decode(try await send("/keys", method: "POST",
                                  json: ["provider": provider, "api_key": apiKey]))
    }
    func listKeys() async throws -> [KeyInfo] {
        try decode(try await send("/keys"))
    }
    func deleteKey(provider: String) async throws -> MessageResponse {
        try decode(try await send("/keys/\(provider)", method: "DELETE"))
    }
    func testKey(provider: String, apiKey: String) async throws -> MessageResponse {
        try decode(try await send("/keys/test", method: "POST",
                                  json: ["provider": provider, "api_key": apiKey]))
    }

    // ---- Chat ----
    func chat(provider: String, message: String, image: String?,
              fileBase64: String? = nil, fileMime: String? = nil,
              attachments: [[String: String]]? = nil,
              model: String?, conversationId: Int?, system: String? = nil,
              webSearch: Bool? = nil, fileIds: [Int]? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["provider": provider, "message": message]
        if let image { body["image"] = image }
        if let fileBase64 { body["file_base64"] = fileBase64 }
        if let fileMime { body["file_mime"] = fileMime }
        if let attachments { body["attachments"] = attachments }
        if let model { body["model"] = model }
        if let conversationId { body["conversation_id"] = conversationId }
        if let system { body["system"] = system }
        if let webSearch { body["web_search"] = webSearch }
        if let fileIds { body["file_ids"] = fileIds }
        return try decode(try await send("/chat", method: "POST", json: body))
    }
    func ensemble(providers: [String], message: String, judge: String?) async throws -> EnsembleResponse {
        var body: [String: Any] = ["providers": providers, "message": message]
        if let judge { body["judge"] = judge }
        return try decode(try await send("/chat/ensemble", method: "POST", json: body))
    }

    // ---- Lịch sử ----
    func conversations() async throws -> [Conversation] {
        try decode(try await send("/conversations"))
    }
    func conversation(_ id: Int) async throws -> ConversationDetail {
        try decode(try await send("/conversations/\(id)"))
    }
    func deleteConversation(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/conversations/\(id)", method: "DELETE"))
    }

    // ---- Admin (users, ban, password, plan, payments, errors, bank) ----
    func adminUsers() async throws -> [AdminUser] {
        try decode(try await send("/admin/users"))
    }
    func adminBan(_ uid: Int, banned: Bool) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/ban", method: "POST", json: ["banned": banned]))
    }
    func adminSetPassword(_ uid: Int, newPassword: String) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/password", method: "POST",
                                  json: ["new_password": newPassword]))
    }
    func adminSetPlan(_ uid: Int, plan: String) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/plan", method: "POST", json: ["plan": plan]))
    }
    func adminSuspend(_ uid: Int, minutes: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/suspend", method: "POST", json: ["minutes": minutes]))
    }
    func adminUnsuspend(_ uid: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/users/\(uid)/unsuspend", method: "POST"))
    }
    func adminSetMaintenance(on: Bool, message: String) async throws -> MessageResponse {
        try decode(try await send("/admin/maintenance", method: "POST",
                                  json: ["on": on, "message": message]))
    }

    // ---- Hồ sơ & trạng thái app ----
    func getMe() async throws -> UserInfo {
        try decode(try await send("/me"))
    }
    func appStatus() async throws -> AppStatus {
        try decode(try await send("/app/status"))
    }
    func sendActivity(_ feature: String) async throws {
        _ = try await send("/me/activity", method: "POST", json: ["feature": feature])
    }

    // ---- Video feed ----
    func createPost(fileId: Int, caption: String, isPublic: Bool = true) async throws -> PostCreateResponse {
        try decode(try await send("/posts", method: "POST",
                                  json: ["file_id": fileId, "caption": caption, "is_public": isPublic]))
    }
    func getFeed() async throws -> [PostItem] {
        try decode(try await send("/feed"))
    }
    func getMyPosts() async throws -> [PostItem] {
        try decode(try await send("/me/posts"))
    }
    func getUserPosts(_ uid: Int) async throws -> [PostItem] {
        try decode(try await send("/users/\(uid)/posts"))
    }
    func likePost(_ pid: Int) async throws -> LikeResponse {
        try decode(try await send("/posts/\(pid)/like", method: "POST"))
    }
    func deletePost(_ pid: Int) async throws -> MessageResponse {
        try decode(try await send("/posts/\(pid)", method: "DELETE"))
    }
    func getComments(_ postId: Int) async throws -> [PostComment] {
        try decode(try await send("/posts/\(postId)/comments"))
    }
    func addComment(postId: Int, content: String) async throws -> PostComment {
        try decode(try await send("/posts/\(postId)/comments", method: "POST", json: ["content": content]))
    }
    func deleteComment(_ cid: Int) async throws -> MessageResponse {
        try decode(try await send("/comments/\(cid)", method: "DELETE"))
    }
    func incrementView(_ postId: Int) async throws {
        _ = try await send("/posts/\(postId)/view", method: "POST")
    }
    func myProfile() async throws -> UserProfile {
        try decode(try await send("/me/profile"))
    }
    func updateProfile(publicId: String?, avatarUrl: String?, bio: String?) async throws -> MessageResponse {
        var body: [String: Any] = [:]
        if let v = publicId { body["public_id"] = v }
        if let v = avatarUrl { body["avatar_url"] = v }
        if let v = bio { body["bio"] = v }
        return try decode(try await send("/me/profile", method: "PUT", json: body))
    }

    // ---- Live ----
    func liveCreate(title: String, hlsUrl: String) async throws -> LiveCreateResponse {
        try decode(try await send("/live/create", method: "POST",
                                  json: ["title": title, "hls_url": hlsUrl]))
    }
    func liveEnd(_ rid: Int) async throws -> MessageResponse {
        try decode(try await send("/live/\(rid)/end", method: "POST"))
    }
    func liveRooms() async throws -> [LiveRoom] {
        try decode(try await send("/live/rooms"))
    }
    func liveInfo(_ rid: Int) async throws -> LiveRoom {
        try decode(try await send("/live/\(rid)"))
    }
    func liveJoin(_ rid: Int) async throws {
        _ = try await send("/live/\(rid)/join", method: "POST")
    }
    func liveLike(_ rid: Int) async throws -> LikesResponse {
        try decode(try await send("/live/\(rid)/like", method: "POST"))
    }
    func liveComment(_ rid: Int, content: String) async throws {
        _ = try await send("/live/\(rid)/comment", method: "POST", json: ["content": content])
    }
    func liveComments(_ rid: Int, after: Int) async throws -> [LiveComment] {
        try decode(try await send("/live/\(rid)/comments?after=\(after)"))
    }

    // ---- Follow / hồ sơ ----
    func follow(_ uid: Int) async throws -> FollowResponse {
        try decode(try await send("/follow/\(uid)", method: "POST"))
    }
    func unfollow(_ uid: Int) async throws -> FollowResponse {
        try decode(try await send("/follow/\(uid)", method: "DELETE"))
    }
    func userProfile(_ uid: Int) async throws -> UserProfile {
        try decode(try await send("/users/\(uid)/profile"))
    }
    /// Tải video của 1 bài về file tạm (có token) để phát trong app.
    func downloadPostVideo(_ pid: Int) async throws -> URL {
        var req = URLRequest(url: try makeURL("/posts/\(pid)/video"))
        req.httpMethod = "GET"
        req.timeoutInterval = 600
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (tempURL, resp) = try await URLSession.shared.download(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.message("Không tải được video.")
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("feed_\(pid).mp4")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(at: tempURL, to: dest)
        return dest
    }
    func adminConfirmPayment(_ pid: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/payments/\(pid)/confirm", method: "POST"))
    }
    func adminErrors() async throws -> [ErrorLog] {
        try decode(try await send("/admin/errors"))
    }
    func adminClearErrors() async throws -> MessageResponse {
        try decode(try await send("/admin/errors", method: "DELETE"))
    }
    func adminGetBank() async throws -> BankSettings {
        try decode(try await send("/admin/payment/settings"))
    }
    func adminSetBank(_ s: BankSettings) async throws -> MessageResponse {
        try decode(try await send("/admin/payment/settings", method: "POST", json: [
            "bank_code": s.bankCode, "bank_short": s.bankShort,
            "bank_account": s.bankAccount, "bank_name": s.bankName,
            "bank_webhook": s.bankWebhook, "bank_apikey": s.bankApikey,
            "acb_api_token": s.acbApiToken
        ]))
    }

    // ---- Giá gói nâng cấp PRO (admin tự chỉnh, VND) ----
    func adminGetPro() async throws -> ProPriceSettings {
        try decode(try await send("/admin/payment/pro"))
    }
    func adminSetPro(price: Int, label: String) async throws -> ProPriceSettings {
        try decode(try await send("/admin/payment/pro", method: "POST",
                                  json: ["price": price, "label": label]))
    }

    // ============================ APP BÁN HÀNG (STORE) ============================
    // -- Khách xem (công khai) --
    func storeConfig() async throws -> StoreAppConfig {
        try decode(try await send("/store/config", auth: false))
    }
    func storeCategories() async throws -> [StoreCategory] {
        try decode(try await send("/store/categories", auth: false))
    }
    func storeShowcase() async throws -> StoreShowcase {
        try decode(try await send("/store/showcase", auth: false))
    }
    // Tất cả sản phẩm gom theo danh mục trong 1 request (id danh mục → danh sách sản phẩm)
    func storeAllProducts() async throws -> [Int: [StoreProduct]] {
        let r: StoreAllProducts = try decode(try await send("/store/all-products", auth: false))
        var out: [Int: [StoreProduct]] = [:]
        for (k, v) in r.byCategory { if let id = Int(k) { out[id] = v } }
        return out
    }
    func storeFolders(categoryId: Int) async throws -> [StoreFolder] {
        try decode(try await send("/store/categories/\(categoryId)/folders", auth: false))
    }
    func storeProducts(folderId: Int) async throws -> [StoreProduct] {
        try decode(try await send("/store/folders/\(folderId)/products", auth: false))
    }
    func storeProduct(_ pid: Int) async throws -> StoreProduct {
        try decode(try await send("/store/products/\(pid)", auth: false))
    }
    func storeProductMine(_ pid: Int) async throws -> StoreProductMine {
        try decode(try await send("/store/products/\(pid)/mine"))
    }
    // Mua bằng số dư ví (giao hàng tức thì)
    func storeBuy(productId: Int, priceId: Int?, promoCode: String? = nil) async throws -> StoreBuyResponse {
        var body: [String: Any] = ["product_id": productId]
        if let priceId { body["price_id"] = priceId }
        if let promoCode, !promoCode.isEmpty { body["promo_code"] = promoCode }
        return try decode(try await send("/store/orders", method: "POST", json: body))
    }
    func storeMyOrders() async throws -> [StoreOrder] {
        try decode(try await send("/store/orders"))
    }
    // Ví cửa hàng
    func storeWallet() async throws -> StoreWallet {
        try decode(try await send("/store/wallet"))
    }
    func storeTopup(amount: Int) async throws -> StoreTopupResponse {
        try decode(try await send("/store/wallet/topup", method: "POST", json: ["amount": amount]))
    }
    // Tải về công khai
    func storeDownloads() async throws -> [StoreDownloadItem] {
        try decode(try await send("/store/downloads", auth: false))
    }
    func storeDownloadURL(productId: Int) -> URL? {
        URL(string: root + "/store/products/\(productId)/download")
    }
    // Admin: % khuyến mãi nạp ví
    func adminGetTopupBonus() async throws -> StoreTopupBonus {
        try decode(try await send("/admin/store/topup-bonus"))
    }
    func adminSetTopupBonus(percent: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/topup-bonus", method: "POST", json: ["percent": percent]))
    }
    // Liên hệ admin & nhóm cộng đồng
    func storeContacts() async throws -> StoreContacts {
        try decode(try await send("/store/contacts", auth: false))
    }
    func adminGetContacts() async throws -> StoreContacts {
        try decode(try await send("/admin/store/contacts"))
    }
    func adminSetContacts(contact: [[String: Any]], groups: [[String: Any]]) async throws -> MessageResponse {
        try decode(try await send("/admin/store/contacts", method: "POST",
                                  json: ["contact": contact, "groups": groups]))
    }

    // -- Admin: giao diện store --
    func adminStoreSetConfig(logoName: String, logoUrl: String,
                             bannerType: String, bannerUrl: String,
                             logoEffect: String? = nil, logoFont: String? = nil,
                             logoAnim: String? = nil, bgType: String? = nil,
                             bgUrl: String? = nil, slogan: String? = nil,
                             sloganFont: String? = nil, sectionOrder: String? = nil,
                             sectionHidden: String? = nil,
                             cardSize: String? = nil, cardScale: Double? = nil,
                             flashEnabled: Bool? = nil, flashProductId: Int? = nil,
                             flashEnd: Int? = nil, flashDiscount: Int? = nil,
                             flashTitle: String? = nil,
                             heroTitle: String? = nil, heroSubtitle: String? = nil,
                             heroEffect: String? = nil, heroFont: String? = nil,
                             heroAnim: String? = nil,
                             sloganEffect: String? = nil,
                             sloganAnim: String? = nil,
                             promoImageUrl: String? = nil,
                             promoProductId: Int? = nil,
                             steps: [[String: String]]? = nil,
                             announceEnabled: Bool? = nil, announceText: String? = nil,
                             announceColor: String? = nil, gamecatLimit: Int? = nil) async throws -> MessageResponse {
        var body: [String: Any] = [
            "logo_name": logoName, "logo_url": logoUrl,
            "banner_type": bannerType, "banner_url": bannerUrl]
        if let flashEnabled { body["flash_enabled"] = flashEnabled }
        if let flashProductId { body["flash_product_id"] = flashProductId }
        if let flashEnd { body["flash_end"] = flashEnd }
        if let flashDiscount { body["flash_discount"] = flashDiscount }
        if let flashTitle { body["flash_title"] = flashTitle }
        if let logoEffect { body["logo_effect"] = logoEffect }
        if let logoFont { body["logo_font"] = logoFont }
        if let logoAnim { body["logo_anim"] = logoAnim }
        if let bgType { body["bg_type"] = bgType }
        if let bgUrl { body["bg_url"] = bgUrl }
        if let slogan { body["slogan"] = slogan }
        if let sloganFont { body["slogan_font"] = sloganFont }
        if let sectionOrder { body["section_order"] = sectionOrder }
        if let sectionHidden { body["section_hidden"] = sectionHidden }
        if let cardSize { body["card_size"] = cardSize }
        if let cardScale { body["card_scale"] = cardScale }
        body["hero_title"] = heroTitle ?? ""
        body["hero_subtitle"] = heroSubtitle ?? ""
        if let heroEffect { body["hero_effect"] = heroEffect }
        if let heroFont { body["hero_font"] = heroFont }
        if let heroAnim { body["hero_anim"] = heroAnim }
        if let sloganEffect { body["slogan_effect"] = sloganEffect }
        if let sloganAnim { body["slogan_anim"] = sloganAnim }
        body["promo_image_url"] = promoImageUrl ?? ""
        if let promoProductId { body["promo_product_id"] = promoProductId }
        if let steps { body["steps"] = steps }
        if let announceEnabled { body["announce_enabled"] = announceEnabled }
        if let announceText { body["announce_text"] = announceText }
        if let announceColor { body["announce_color"] = announceColor }
        if let gamecatLimit { body["gamecat_limit"] = gamecatLimit }
        return try decode(try await send("/admin/store/config", method: "POST", json: body))
    }
    // Lưu ảnh từ máy → trả về link URL tuyệt đối (dùng dán vào logo/banner/media)
    func mediaUpload(dataBase64: String, mime: String, name: String) async throws -> String {
        let r: MediaUploadResponse = try decode(try await send("/media/upload", method: "POST",
            json: ["data_base64": dataBase64, "mime": mime, "name": name]))
        return root + r.path
    }
    // -- Admin: danh mục / thư mục / sản phẩm --
    func adminStoreSaveCategory(id: Int?, name: String, media: [[String: String]]) async throws -> IdResponse {
        var body: [String: Any] = ["name": name, "media": media]
        if let id { body["id"] = id }
        return try decode(try await send("/admin/store/categories", method: "POST", json: body))
    }
    func adminStoreDeleteCategory(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/categories/\(id)", method: "DELETE"))
    }
    func adminStoreSaveFolder(id: Int?, categoryId: Int, name: String,
                              media: [[String: String]]) async throws -> IdResponse {
        var body: [String: Any] = ["category_id": categoryId, "name": name, "media": media]
        if let id { body["id"] = id }
        return try decode(try await send("/admin/store/folders", method: "POST", json: body))
    }
    func adminStoreDeleteFolder(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/folders/\(id)", method: "DELETE"))
    }
    func adminStoreSaveProduct(id: Int?, folderId: Int, name: String, description: String,
                               media: [[String: String]], downloadUrl: String,
                               downloadFileId: Int?, kind: String) async throws -> IdResponse {
        var body: [String: Any] = ["folder_id": folderId, "name": name,
                                    "description": description, "media": media,
                                    "download_url": downloadUrl, "kind": kind]
        if let id { body["id"] = id }
        if let downloadFileId { body["download_file_id"] = downloadFileId }
        return try decode(try await send("/admin/store/products", method: "POST", json: body))
    }
    func adminStoreDeleteProduct(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/products/\(id)", method: "DELETE"))
    }
    // -- Admin: giá theo thời hạn --
    func adminStoreSetPrices(productId: Int, prices: [[String: Any]]) async throws -> MessageResponse {
        try decode(try await send("/admin/store/products/\(productId)/prices",
                                  method: "POST", json: ["prices": prices]))
    }
    // -- Admin: kho key --
    func adminStoreListKeys(productId: Int) async throws -> StoreKeysInfo {
        try decode(try await send("/admin/store/products/\(productId)/keys"))
    }
    func adminStoreAddKeys(productId: Int, text: String, priceId: Int? = nil) async throws -> MessageResponse {
        var body: [String: Any] = ["text": text]
        if let priceId { body["price_id"] = priceId }
        return try decode(try await send("/admin/store/products/\(productId)/keys",
                                  method: "POST", json: body))
    }
    func adminStoreDeleteKey(_ keyId: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/keys/\(keyId)", method: "DELETE"))
    }
    func adminStoreDeleteAvailableKeys(productId: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/products/\(productId)/keys", method: "DELETE"))
    }
    func adminStoreOrders() async throws -> [StoreAdminOrder] {
        try decode(try await send("/admin/store/orders"))
    }
    func adminStoreInventory() async throws -> StoreInventory {
        try decode(try await send("/admin/store/inventory"))
    }

    // Nạp/trừ ví cửa hàng thủ công cho người dùng (theo publicId hoặc username)
    func adminAdjustStoreWallet(userIdentifier: String, delta: Int, note: String) async throws -> MessageResponse {
        try decode(try await send("/admin/store/wallet/adjust", method: "POST", json: [
            "user": userIdentifier,
            "delta": delta,
            "note": note.isEmpty ? (delta >= 0 ? "Admin nạp ví" : "Admin trừ ví") : note
        ]))
    }

    // Lấy danh sách người dùng của cửa hàng để admin điều chỉnh ví
    func adminStoreUsers() async throws -> [AdminUser] {
        try decode(try await send("/admin/users"))
    }

    // ---- Admin API keys (server-side) ----
    func adminSaveKey(provider: String, apiKey: String) async throws -> MessageResponse {
        try decode(try await send("/admin/keys", method: "POST",
                                  json: ["provider": provider, "api_key": apiKey]))
    }
    func adminListKeys() async throws -> [AdminKeyInfo] {
        try decode(try await send("/admin/keys"))
    }
    func adminDeleteKey(provider: String) async throws -> MessageResponse {
        try decode(try await send("/admin/keys/\(provider)", method: "DELETE"))
    }

    // ---- Admin thống kê ----
    func adminStats() async throws -> AdminStats {
        try decode(try await send("/admin/stats"))
    }

    // ---- Mã khuyến mãi ----
    func storeValidatePromo(code: String, amount: Int) async throws -> PromoValidateResult {
        try decode(try await send("/store/promo/validate", method: "POST",
                                  json: ["code": code, "amount": amount]))
    }
    func adminListPromoCodes() async throws -> [PromoCode] {
        try decode(try await send("/admin/store/promo-codes"))
    }
    func adminCreatePromoCode(code: String, discountType: String, discountValue: Int,
                              minAmount: Int, maxUses: Int, expiresAt: Int) async throws -> IdResponse {
        try decode(try await send("/admin/store/promo-codes", method: "POST", json: [
            "code": code, "discount_type": discountType, "discount_value": discountValue,
            "min_amount": minAmount, "max_uses": maxUses, "expires_at": expiresAt
        ]))
    }
    func adminDeletePromoCode(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/admin/store/promo-codes/\(id)", method: "DELETE"))
    }

    // ---- Push Notification ----
    func registerDeviceToken(_ token: String) async throws -> MessageResponse {
        try decode(try await send("/device-token", method: "POST",
                                  json: ["token": token, "platform": "ios"]))
    }
    func unregisterDeviceToken(_ token: String) async throws -> MessageResponse {
        try decode(try await send("/device-token", method: "DELETE", json: ["token": token]))
    }
    func adminSendPushNotification(title: String, body: String, target: String = "all") async throws -> PushSendResult {
        try decode(try await send("/admin/push-notification", method: "POST",
                                  json: ["title": title, "body": body, "target": target]))
    }
    func adminPushDeviceStats() async throws -> PushDeviceStats {
        try decode(try await send("/admin/push-notification/devices"))
    }

    // ---- File ----
    func listFiles(category: String?) async throws -> [FileItem] {
        var path = "/files"
        if let category, category != "all" { path += "?category=\(category)" }
        return try decode(try await send(path))
    }
    func uploadFile(name: String, category: String, dataBase64: String) async throws -> UploadResponse {
        try decode(try await send("/files", method: "POST",
                                  json: ["name": name, "category": category, "data_base64": dataBase64]))
    }
    func uploadFileRaw(name: String, category: String, fileURL: URL) async throws -> UploadResponse {
        var path = "/files/upload?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)"
        if !category.isEmpty {
            path += "&category=\(category.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? category)"
        }
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        let ext = fileURL.pathExtension.lowercased()
        let mime = mimeType(for: ext)
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        
        let (data, resp) = try await URLSession.shared.upload(for: req, fromFile: fileURL)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("Phản hồi không hợp lệ.")
        }
        if !(200..<300).contains(http.statusCode) {
            var detail = "Lỗi tải lên (\(http.statusCode))."
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = obj["detail"] as? String { detail = d }
            throw APIError.message(detail)
        }
        return try decode(data)
    }
    func downloadFile(_ id: Int) async throws -> FileDetail {
        try decode(try await send("/files/\(id)"))
    }
    func downloadFileRaw(_ id: Int) async throws -> (URL, String) {
        var req = URLRequest(url: try makeURL("/files/\(id)/download"))
        req.httpMethod = "GET"
        req.timeoutInterval = 600
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        
        let (tempURL, resp) = try await URLSession.shared.download(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("Phản hồi không hợp lệ.")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.message("Lỗi tải xuống (\(http.statusCode)).")
        }
        
        var filename = "file"
        if let disp = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let range = disp.range(of: "filename=\"") {
                let start = range.upperBound
                if let endRange = disp.range(of: "\"", range: start..<disp.endIndex) {
                    filename = String(disp[start..<endRange.lowerBound])
                }
            } else if let range = disp.range(of: "filename=") {
                let start = range.upperBound
                filename = String(disp[start...])
            }
        }
        return (tempURL, filename)
    }
    func deleteFile(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/files/\(id)", method: "DELETE"))
    }
    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        case "html": return "text/html"
        case "css": return "text/css"
        case "js": return "application/javascript"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // ---- Giọng nói ----
    func transcribe(provider: String, audioBase64: String, mime: String) async throws -> VoiceResponse {
        try decode(try await send("/voice/transcribe", method: "POST",
                                  json: ["provider": provider, "audio_base64": audioBase64, "mime": mime]))
    }
    
    // ---- Giọng nói nâng cao (TTS) ----
    func synthesizeSpeech(text: String, provider: String) async throws -> String {
        let body: [String: Any] = ["text": text, "provider": provider]
        let data = try await send("/voice/synthesize", method: "POST", json: body)
        struct TTSResponse: Decodable { let audioBase64: String }
        let res: TTSResponse = try decode(data)
        return res.audioBase64
    }

    // ---- Sinh ảnh AI ----
    struct ImageGenResponse: Decodable {
        let id: Int
        let name: String
        let dataBase64: String
        let mime: String
    }
    func generateImage(prompt: String, provider: String) async throws -> ImageGenResponse {
        let body: [String: Any] = ["prompt": prompt, "provider": provider]
        return try decode(try await send("/image/generate", method: "POST", json: body))
    }

    // ---- Chạy code / Sandbox ----
    func runPython(code: String, stdin: String? = nil) async throws -> CodeRunResult {
        var body: [String: Any] = ["code": code]
        if let stdin { body["stdin"] = stdin }
        return try decode(try await send("/run/python", method: "POST", json: body))
    }
    func runCode(language: String, code: String, stdin: String? = nil) async throws -> CodeRunResult {
        var body: [String: Any] = ["code": code, "language": language]
        if let stdin { body["stdin"] = stdin }
        return try decode(try await send("/run/code", method: "POST", json: body))
    }
    func runTestFile(fileId: Int, args: String? = nil) async throws -> FileRunResult {
        var body: [String: Any] = ["file_id": fileId]
        if let args { body["args"] = args }
        return try decode(try await send("/run/test", method: "POST", json: body))
    }

    // ---- AI lập trình (review/debug/explain/convert/test/optimize/document/security) ----
    func codeAI(provider: String, code: String, language: String?, task: String,
                targetLang: String? = nil, model: String? = nil) async throws -> CodeAIResult {
        var body: [String: Any] = ["provider": provider, "code": code, "task": task]
        if let language { body["language"] = language }
        if let targetLang { body["target_lang"] = targetLang }
        if let model { body["model"] = model }
        return try decode(try await send("/code/ai", method: "POST", json: body))
    }

    // ---- Credits & Thanh toán ----
    func myCredits() async throws -> CreditsResponse {
        try decode(try await send("/me/credits"))
    }
    func paymentPackages() async throws -> [PaymentPackage] {
        try decode(try await send("/payment/packages", auth: false))
    }
    func createPayment(package: String, amount: Int) async throws -> PaymentCreateResponse {
        try decode(try await send("/payment/create", method: "POST",
                                  json: ["package": package, "amount": amount]))
    }
    func paymentHistory() async throws -> [PaymentRecord] {
        try decode(try await send("/payment/history"))
    }
    func cancelPayment(id: Int) async throws -> MessageResponse {
        try decode(try await send("/payment/cancel", method: "POST", json: ["id": id]))
    }

    // ---- Prompt mẫu ----
    func listPrompts() async throws -> [PromptTemplate] {
        try decode(try await send("/prompts"))
    }
    func createPrompt(title: String, content: String, category: String?, isPublic: Bool) async throws -> MessageResponse {
        var body: [String: Any] = ["title": title, "content": content, "is_public": isPublic]
        if let category { body["category"] = category }
        return try decode(try await send("/prompts", method: "POST", json: body))
    }
    func deletePrompt(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/prompts/\(id)", method: "DELETE"))
    }

    // ---- Chia sẻ hội thoại ----
    func shareConversation(_ id: Int) async throws -> ShareResponse {
        try decode(try await send("/conversations/\(id)/share", method: "POST"))
    }

    // ---- Xuất hội thoại (raw data) ----
    func exportConversation(_ id: Int, format: String) async throws -> Data {
        try await send("/conversations/\(id)/export?format=\(format)")
    }

    // ---- Tìm kiếm tin nhắn ----
    func searchMessages(query: String) async throws -> [SearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try decode(try await send("/search?q=\(encoded)"))
    }

    // ---- Tin nhắn yêu thích ----
    func listFavorites() async throws -> [FavoriteMessage] {
        try decode(try await send("/favorites"))
    }
    func addFavorite(content: String, conversationId: Int?, provider: String?) async throws -> MessageResponse {
        var body: [String: Any] = ["content": content]
        if let conversationId { body["conversation_id"] = conversationId }
        if let provider { body["provider"] = provider }
        return try decode(try await send("/favorites", method: "POST", json: body))
    }
    func removeFavorite(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/favorites/\(id)", method: "DELETE"))
    }

    // ---- Ghim hội thoại ----
    func pinConversation(_ id: Int) async throws -> MessageResponse {
        try decode(try await send("/conversations/\(id)/pin", method: "POST"))
    }

    // ---- Zip code ----
    func zipCode(text: String) async throws -> ZipResponse {
        try decode(try await send("/code/zip", method: "POST", json: ["text": text]))
    }

    // ---- Phân hệ mạng xã hội ----
    func socialGenerate(topic: String, platform: String, tone: String, mode: String, provider: String) async throws -> SocialGenResponse {
        let body: [String: Any] = [
            "topic": topic,
            "platform": platform,
            "tone": tone,
            "mode": mode,
            "provider": provider
        ]
        return try decode(try await send("/social/generator", method: "POST", json: body))
    }

    func socialDownload(url: String, quality: String = "1080") async throws -> SocialDownloadResponse {
        let body: [String: Any] = ["url": url, "quality": quality]
        return try decode(try await send("/social/download", method: "POST", json: body))
    }

    func getFacebookStreamKey(accessToken: String) async throws -> StreamKeyResponse {
        let body: [String: Any] = ["access_token": accessToken]
        return try decode(try await send("/social/stream/facebook", method: "POST", json: body))
    }

    func getTikTokStreamKey(cookies: String) async throws -> StreamKeyResponse {
        let body: [String: Any] = ["cookies": cookies]
        return try decode(try await send("/social/stream/tiktok", method: "POST", json: body))
    }

    // ---- TikTok Live: đọc bình luận tự động (như TikFinity) ----
    func tiktokLiveConnect(username: String) async throws -> TikTokLiveStatus {
        try decode(try await send("/social/tiktok/live/connect", method: "POST",
                                  json: ["username": username]))
    }
    func tiktokLiveEvents(username: String, after: Int) async throws -> TikTokLiveEventsResponse {
        let q = username.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? username
        return try decode(try await send("/social/tiktok/live/events?username=\(q)&after=\(after)"))
    }
    func tiktokLiveDisconnect(username: String) async throws {
        _ = try await send("/social/tiktok/live/disconnect", method: "POST",
                           json: ["username": username])
    }

    // ---- Dịch sang tiếng Việt (cho TTS đa ngôn ngữ) ----
    func translate(text: String, target: String = "vi", source: String = "auto") async throws -> TranslateResponse {
        try decode(try await send("/translate", method: "POST",
                                  json: ["text": text, "target": target, "source": source]))
    }

    // ---- KENIOS AI: cấp API key cho người khác ----
    func apiTokenCreate(name: String) async throws -> ApiTokenCreateResponse {
        try decode(try await send("/apitokens/create", method: "POST", json: ["name": name]))
    }
    func apiTokenList() async throws -> ApiTokenListResponse {
        try decode(try await send("/apitokens"))
    }
    func apiTokenDelete(token: String) async throws {
        _ = try await send("/apitokens/\(token)", method: "DELETE")
    }

    // ---- Thiết bị đăng ký (UDID) ----
    func listDevices() async throws -> DevicesResponse {
        try decode(try await send("/devices"))
    }

    func encryptCode(code: String, language: String, level: String) async throws -> EncryptResponse {
        let body: [String: Any] = ["code": code, "language": language, "level": level]
        return try decode(try await send("/code/encrypt", method: "POST", json: body))
    }

    func analyzeBinary(fileURL: URL) async throws -> BinaryAnalysisResponse {
        var req = URLRequest(url: try makeURL("/code/analyze"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        let filename = fileURL.lastPathComponent
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: fileURL))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.message("Phản hồi không hợp lệ.")
        }
        if !(200..<300).contains(http.statusCode) {
            throw APIError.message("Lỗi phân tích (\(http.statusCode)).")
        }
        return try decode(data)
    }

    func translateAsm(input: String, mode: String, arch: String, provider: String) async throws -> AsmResponse {
        let body: [String: Any] = [
            "input": input,
            "mode": mode,
            "arch": arch,
            "provider": provider
        ]
        return try decode(try await send("/code/asm", method: "POST", json: body))
    }

    // ---- DevOps & DevOps Tools ----
    func runSSH(host: String, user: String, pass: String, cmd: String) async throws -> SSHResultResponse {
        let body: [String: Any] = [
            "host": host,
            "username": user,
            "password": pass,
            "command": cmd
        ]
        return try decode(try await send("/run/ssh", method: "POST", json: body))
    }

    func runHTTP(url: String, method: String, headers: [String: String], body: String) async throws -> HTTPTestResponse {
        let body: [String: Any] = [
            "url": url,
            "method": method,
            "headers": headers,
            "body": body
        ]
        return try decode(try await send("/run/http", method: "POST", json: body))
    }

    func runSQL(query: String) async throws -> SQLResultResponse {
        let body: [String: Any] = [
            "query": query
        ]
        return try decode(try await send("/run/sql", method: "POST", json: body))
    }

    func cleanupDatabase(days: Int) async throws -> CleanupResponse {
        let body: [String: Any] = ["days": days]
        return try decode(try await send("/db/cleanup", method: "POST", json: body))
    }

    // ---- Bạn bè & Tin nhắn trực tiếp (User-to-User) ----
    func searchUsers(query: String) async throws -> [UserSearchResult] {
        try decode(try await send("/users/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"))
    }

    func sendFriendRequest(friendId: Int) async throws -> MessageResponse {
        try decode(try await send("/friends/request", method: "POST", json: ["friend_id": friendId]))
    }

    func listFriendRequests() async throws -> [FriendRequestItem] {
        try decode(try await send("/friends/requests"))
    }

    func respondToFriendRequest(requestId: Int, action: String) async throws -> MessageResponse {
        try decode(try await send("/friends/respond", method: "POST", json: ["request_id": requestId, "action": action]))
    }

    func listFriends() async throws -> [FriendItem] {
        try decode(try await send("/friends"))
    }

    func getDirectMessages(friendId: Int) async throws -> [DirectMessageItem] {
        try decode(try await send("/direct_messages/\(friendId)"))
    }

    func sendDirectMessage(receiverId: Int, content: String) async throws -> MessageResponse {
        try decode(try await send("/direct_messages", method: "POST", json: ["receiver_id": receiverId, "content": content]))
    }

}

