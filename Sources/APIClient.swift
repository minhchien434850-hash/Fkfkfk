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

    var root: String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.lowercased().hasPrefix("http") { s = "http://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func makeURL(_ path: String) throws -> URL {
        guard let u = URL(string: root + path) else {
            throw APIError.message("URL máy chủ không hợp lệ.")
        }
        return u
    }

    func send(_ path: String, method: String = "GET",
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

    func decode<T: Decodable>(_ data: Data) throws -> T {
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
                  code: String? = nil, deviceId: String? = nil) async throws -> AuthResponse {
        var body: [String: Any] = ["username": username, "password": password]
        if let email, !email.isEmpty { body["email"] = email }
        if let phone, !phone.isEmpty { body["phone"] = phone }
        if let code, !code.isEmpty { body["code"] = code }
        if let deviceId, !deviceId.isEmpty { body["device_id"] = deviceId }
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

    // Gửi mã xác nhận (OTP) qua email hoặc số điện thoại (SMS)
    func sendOtp(email: String = "", phone: String = "", purpose: String = "register") async throws -> OtpSendResponse {
        var json: [String: Any] = ["purpose": purpose]
        if !email.isEmpty { json["email"] = email }
        if !phone.isEmpty { json["phone"] = phone }
        return try decode(try await send("/auth/send-otp", method: "POST", json: json, auth: false))
    }
    func login(_ username: String, _ password: String) async throws -> AuthResponse {
        try decode(try await send("/auth/login", method: "POST",
                                  json: ["username": username, "password": password], auth: false))
    }
    /// Đăng nhập KHÔNG MẬT KHẨU bằng mã OTP gửi Gmail/SĐT (có tài khoản → vào; chưa có → tự tạo).
    func loginOtp(email: String = "", phone: String = "", code: String,
                  deviceId: String? = nil) async throws -> AuthResponse {
        var json: [String: Any] = ["code": code]
        if !email.isEmpty { json["email"] = email }
        if !phone.isEmpty { json["phone"] = phone }
        if let deviceId, !deviceId.isEmpty { json["device_id"] = deviceId }
        return try decode(try await send("/auth/login-otp", method: "POST", json: json, auth: false))
    }
    /// Đăng nhập bằng tài khoản Google: gửi id_token (Google OAuth) cho server xác thực.
    func googleLogin(idToken: String, deviceId: String? = nil) async throws -> AuthResponse {
        var json: [String: Any] = ["id_token": idToken]
        if let deviceId, !deviceId.isEmpty { json["device_id"] = deviceId }
        return try decode(try await send("/auth/google", method: "POST", json: json, auth: false))
    }
    /// Lưu âm thanh thông báo DÙNG CHUNG (toàn cục) lên máy chủ — mọi người đều thấy.
    func saveNotifSounds(_ sounds: [String: Any]) async throws {
        _ = try await send("/notif-sounds", method: "POST", json: ["sounds": sounds])
    }
    /// Đọc âm thanh thông báo dùng chung (toàn cục) — trả về chuỗi JSON ("" nếu chưa đặt).
    func getNotifSounds() async throws -> String {
        struct R: Decodable { let json: String }
        let r: R = try decode(try await send("/notif-sounds", auth: true))
        return r.json
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
    func adminSetPlan(_ uid: Int, plan: String, days: Int? = nil) async throws -> MessageResponse {
        var body: [String: Any] = ["plan": plan]
        if let days { body["days"] = days }
        return try decode(try await send("/admin/users/\(uid)/plan", method: "POST", json: body))
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
    // Bảng tin mạng xã hội (ảnh + tin chữ, không gồm video)
    func getSocialFeed() async throws -> [PostItem] {
        try decode(try await send("/social/feed"))
    }
    // Lưu / bỏ lưu bài (bookmark)
    @discardableResult
    func savePost(_ pid: Int) async throws -> SaveResponse {
        try decode(try await send("/posts/\(pid)/save", method: "POST"))
    }
    func getSavedPosts() async throws -> [PostItem] {
        try decode(try await send("/me/saved"))
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
    // §1.1 — Danh sách thông báo phát cho mọi người (app poll để hiện trong app)
    func getNotifications(limit: Int = 20) async throws -> [AppNotification] {
        try decode(try await send("/notifications?limit=\(limit)"))
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
    func adminSetPro(package: String, price: Int) async throws -> ProPriceSettings {
        try decode(try await send("/admin/payment/pro", method: "POST",
                                  json: ["package": package, "price": price]))
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
    // Gửi đánh giá sản phẩm (để đếm "lượt đánh giá") — bỏ qua nếu lỗi
    @discardableResult
    func storeReview(productId: Int, stars: Int) async throws -> MessageResponse {
        try decode(try await send("/store/products/\(productId)/review", method: "POST",
                                  json: ["stars": stars]))
    }
    // Tăng lượt xem sản phẩm (mỗi lần khách bấm vào +1)
    func storeProductView(productId: Int) async throws {
        _ = try await send("/store/products/\(productId)/view", method: "POST")
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
                             logoType: String? = nil,
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
                             heroAnim: String? = nil, heroColor: String? = nil,
                             heroSubEffect: String? = nil, heroSubFont: String? = nil,
                             heroSubAnim: String? = nil, heroSubColor: String? = nil,
                             sloganEffect: String? = nil,
                             sloganAnim: String? = nil, sloganColor: String? = nil,
                             promoImageUrl: String? = nil,
                             promoProductId: Int? = nil,
                             statUsersBase: Int? = nil, statSoldBase: Int? = nil,
                             statReviewsBase: Int? = nil,
                             announceEnabled: Bool? = nil, announceText: String? = nil,
                             announceColor: String? = nil, gamecatLimit: Int? = nil,
                             welcomePopupEnabled: Bool? = nil, welcomePopupTitle: String? = nil,
                             welcomePopupText: String? = nil,
                             welcomeVoiceEnabled: Bool? = nil, welcomeVoiceText: String? = nil,
                             welcomeVoiceRate: Float? = nil,
                             latestVersion: String? = nil, updateUrl: String? = nil,
                             updateMessage: String? = nil) async throws -> MessageResponse {
        var body: [String: Any] = [
            "logo_name": logoName, "logo_url": logoUrl,
            "banner_type": bannerType, "banner_url": bannerUrl]
        if let logoType { body["logo_type"] = logoType }
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
        if let heroColor { body["hero_color"] = heroColor }
        body["hero_sub_effect"] = heroSubEffect ?? ""
        if let heroSubFont { body["hero_sub_font"] = heroSubFont }
        if let heroSubAnim { body["hero_sub_anim"] = heroSubAnim }
        if let heroSubColor { body["hero_sub_color"] = heroSubColor }
        if let sloganEffect { body["slogan_effect"] = sloganEffect }
        if let sloganAnim { body["slogan_anim"] = sloganAnim }
        if let sloganColor { body["slogan_color"] = sloganColor }
        body["promo_image_url"] = promoImageUrl ?? ""
        if let promoProductId { body["promo_product_id"] = promoProductId }
        if let statUsersBase { body["stat_users_base"] = statUsersBase }
        if let statSoldBase { body["stat_sold_base"] = statSoldBase }
        if let statReviewsBase { body["stat_reviews_base"] = statReviewsBase }
        if let announceEnabled { body["announce_enabled"] = announceEnabled }
        if let announceText { body["announce_text"] = announceText }
        if let announceColor { body["announce_color"] = announceColor }
        if let gamecatLimit { body["gamecat_limit"] = gamecatLimit }
        if let welcomePopupEnabled { body["welcome_popup_enabled"] = welcomePopupEnabled }
        if let welcomePopupTitle { body["welcome_popup_title"] = welcomePopupTitle }
        if let welcomePopupText { body["welcome_popup_text"] = welcomePopupText }
        if let welcomeVoiceEnabled { body["welcome_voice_enabled"] = welcomeVoiceEnabled }
        if let welcomeVoiceText { body["welcome_voice_text"] = welcomeVoiceText }
        if let welcomeVoiceRate { body["welcome_voice_rate"] = welcomeVoiceRate }
        if let latestVersion { body["latest_version"] = latestVersion }
        if let updateUrl { body["update_url"] = updateUrl }
        if let updateMessage { body["update_message"] = updateMessage }
        return try decode(try await send("/admin/store/config", method: "POST", json: body))
    }
    // §7 — Đa người bán: cửa hàng cá nhân
    func getMyStore() async throws -> MyStoreResponse {
        try decode(try await send("/my-store"))
    }
    func saveMyStore(name: String, description: String?, logoUrl: String?,
                     bannerUrl: String? = nil, slogan: String? = nil) async throws -> MyStore {
        var body: [String: Any] = ["name": name]
        if let description { body["description"] = description }
        if let logoUrl { body["logo_url"] = logoUrl }
        if let bannerUrl { body["banner_url"] = bannerUrl }
        if let slogan { body["slogan"] = slogan }
        struct R: Decodable { let store: MyStore }
        let r: R = try decode(try await send("/my-store", method: "POST", json: body))
        return r.store
    }
    func saveMyProduct(id: Int?, name: String, description: String?, price: Int,
                       media: [[String: String]], downloadUrl: String?, categoryId: Int? = nil) async throws {
        var body: [String: Any] = ["name": name, "price": price, "media": media]
        if let id { body["id"] = id }
        if let description { body["description"] = description }
        if let downloadUrl { body["download_url"] = downloadUrl }
        if let categoryId { body["category_id"] = categoryId }
        _ = try await send("/my-store/products", method: "POST", json: body)
    }
    func deleteMyProduct(_ pid: Int) async throws {
        _ = try await send("/my-store/products/\(pid)", method: "DELETE")
    }
    // §7 Đợt 2 — Danh mục cửa hàng cá nhân
    func addMyCategory(name: String) async throws {
        _ = try await send("/my-store/categories", method: "POST", json: ["name": name])
    }
    func deleteMyCategory(_ cid: Int) async throws {
        _ = try await send("/my-store/categories/\(cid)", method: "DELETE")
    }
    func getUserStore(_ sid: Int) async throws -> MyStoreResponse {
        try decode(try await send("/u-store/\(sid)"))
    }

    // §9.1 — Cảnh báo xâm nhập qua Telegram (admin)
    func getSecurityAlert() async throws -> SecurityAlertConfig {
        try decode(try await send("/admin/security-alert"))
    }
    func setSecurityAlert(enabled: Bool? = nil, botToken: String? = nil,
                          chatId: String? = nil, test: Bool? = nil) async throws {
        var body: [String: Any] = [:]
        if let enabled { body["enabled"] = enabled }
        if let botToken { body["bot_token"] = botToken }
        if let chatId { body["chat_id"] = chatId }
        if let test { body["test"] = test }
        _ = try await send("/admin/security-alert", method: "POST", json: body)
    }

    // Lưu ảnh từ máy → trả về link URL tuyệt đối (dùng dán vào logo/banner/media)
    func mediaUpload(dataBase64: String, mime: String, name: String) async throws -> String {
        let r: MediaUploadResponse = try decode(try await send("/media/upload", method: "POST",
            json: ["data_base64": dataBase64, "mime": mime, "name": name]))
        return root + r.path
    }
    // Tải ảnh/video lên (công khai /media/{id}) → trả về FILE ID để đăng bài
    func mediaUploadId(dataBase64: String, mime: String, name: String) async throws -> Int {
        let r: MediaUploadResponse = try decode(try await send("/media/upload", method: "POST",
            json: ["data_base64": dataBase64, "mime": mime, "name": name]))
        return r.id
    }
    /// URL công khai của 1 file media theo id (ảnh/video bài đăng) — tải bằng AsyncImage được.
    func mediaURL(fileId: Int) -> URL? { URL(string: "\(root)/media/\(fileId)") }
}
