import Foundation

extension APIClient {
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
    func mimeType(for ext: String) -> String {
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
