import Foundation

struct Provider: Identifiable, Decodable, Hashable {
    let id: String
    let label: String
    let models: [String]
    let defaultModel: String
    let vision: Bool
    let free: Bool
    let code: Bool?
}

struct UserInfo: Decodable, Hashable {
    let id: Int
    let username: String
    let email: String?
    let phone: String?
    let publicId: String?
    let isAdmin: Bool?
    let plan: String?
    let credits: Int?
    let lang: String?
    let status: String?
}

struct AuthResponse: Decodable { let token: String; let user: UserInfo }

struct SavedFile: Decodable, Hashable { let id: Int; let name: String }

struct ChatResponse: Decodable {
    let reply: String
    let conversationId: Int
    let provider: String
    let savedFiles: [SavedFile]?
    let tokensUsed: Int?
}

struct EnsembleResponse: Decodable {
    let best: String
    let judge: String
    let answers: [String: String]
}

struct Conversation: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String?
    let provider: String?
    let updatedAt: Int?
    let pinned: Int?
    let shareToken: String?
}

struct ChatMessage: Identifiable, Decodable {
    let id = UUID()
    let role: String
    let content: String
    var provider: String? = nil
    enum CodingKeys: String, CodingKey { case role, content }
    init(role: String, content: String, provider: String? = nil) {
        self.role = role; self.content = content; self.provider = provider
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        provider = nil
    }
}

struct ConversationDetail: Decodable {
    let conversationId: Int
    let messages: [ChatMessage]
}

struct MessageResponse: Decodable { let message: String }
struct ForgotResponse: Decodable { let message: String; let resetToken: String? }
struct KeyInfo: Decodable { let provider: String; let configured: Bool }
struct ServerConfig: Decodable { let name: String; let providers: [Provider] }
struct VoiceResponse: Decodable { let text: String }

struct FileItem: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let category: String?
    let size: Int?
    let createdAt: Int?
}
struct FileDetail: Decodable {
    let name: String
    let category: String?
    let dataBase64: String
}
struct UploadResponse: Decodable { let id: Int; let name: String; let size: Int }

struct AdminUser: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String
    let email: String?
    let phone: String?
    let publicId: String?
    let isAdmin: Bool?
    let banned: Int?
    let plan: String?
    let credits: Int?
    let status: String?
    let suspendUntil: Int?
    let lastSeen: Int?
    let lastFeature: String?
    let createdAt: Int?
}

struct ServerProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var type: String   // "VPS" | "Hosting"
    var url: String
}

// ---- Sandbox / Code tools ----
struct CodeRunResult: Decodable {
    let stdout: String
    let stderr: String
    let returncode: Int
}
struct FileRunResult: Decodable, Identifiable {
    let id = UUID()
    let file: String
    let stdout: String
    let stderr: String
    let returncode: Int
    enum CodingKeys: String, CodingKey { case file, stdout, stderr, returncode }
}
struct CodeAIResult: Decodable {
    let result: String
    let task: String
    let provider: String
}

// ---- Thanh toán / Credits ----
struct CreditsResponse: Decodable {
    let credits: Int
    let plan: String
}
struct PaymentPackage: Identifiable, Decodable, Hashable {
    let id: String
    let credits: Int
    let amount: Int
    let label: String
}
struct BankInfo: Decodable {
    let bank: String
    let account: String
    let name: String
    let content: String
}
struct PaymentCreateResponse: Decodable {
    let paymentId: Int
    let ref: String
    let amount: Int
    let credits: Int
    let label: String
    let message: String
    let bankInfo: BankInfo
    let qrUrl: String?
}
struct PaymentRecord: Identifiable, Decodable, Hashable {
    let id: Int
    let amount: Int
    let credits: Int
    let status: String
    let ref: String?
    let createdAt: Int?
}

struct ErrorLog: Identifiable, Decodable, Hashable {
    let id: Int
    let userId: Int?
    let username: String?
    let context: String?
    let detail: String?
    let createdAt: Int?
}

struct BankSettings: Decodable, Hashable {
    var bankCode: String
    var bankShort: String
    var bankAccount: String
    var bankName: String
    var bankWebhook: String
    var bankApikey: String = ""
    var acbApiToken: String = ""
}

// ---- Đính kèm (Attachment) ----
struct AttachmentItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var data: Data
    var mime: String
    var type: String  // "image" or "file"
    var selected: Bool = true
    var thumbnail: Data?  // for image preview
}

// ---- Prompt mẫu ----
struct PromptTemplate: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String
    let content: String
    let category: String?
    let isPublic: Int?
    let userId: Int?
}

// ---- Chia sẻ hội thoại ----
struct ShareResponse: Decodable { let shareToken: String; let shareUrl: String }

// ---- Tìm kiếm tin nhắn ----
struct SearchResult: Identifiable, Decodable, Hashable {
    let id: Int
    let conversationId: Int
    let conversationTitle: String?
    let role: String
    let snippet: String
}

// ---- Tin nhắn yêu thích ----
struct FavoriteMessage: Identifiable, Decodable, Hashable {
    let id: Int
    let messageContent: String
    let conversationId: Int?
    let provider: String?
    let createdAt: Int?
}

// ---- Cài đặt giá gói nâng cấp PRO (admin) ----
struct ProPriceSettings: Decodable, Hashable {
    let price: Int
    let label: String
}

// ============================ APP BÁN HÀNG (STORE) ============================
struct StoreMedia: Decodable, Hashable {
    let type: String   // image | video
    let url: String
}

struct StoreAppConfig: Decodable, Hashable {
    let logoName: String
    let logoUrl: String
    let bannerType: String   // image | video
    let bannerUrl: String
    let topupBonusPercent: Int?
    var logoEffect: String? = nil   // rainbow|none|glow|neon|gold
    var logoFont: String? = nil     // rounded|serif|mono|default
    var logoAnim: String? = nil     // shimmer|wave|pulse|none
    var bgType: String? = nil       // none|image|video
    var bgUrl: String? = nil
    var slogan: String? = nil       // dòng giới thiệu dưới tên cửa hàng
    var sloganFont: String? = nil   // rounded|serif|mono|default|...
    var sectionOrder: String? = nil // thứ tự bố cục: categories,products,downloads,contacts,wishlist,recent
    var sectionHidden: String? = nil // các mục bị admin ẩn (cho gọn)
    var cardSize: String? = nil     // small | medium | large — kích cỡ thẻ sản phẩm/danh mục
    var cardScale: String? = nil    // hệ số kéo kích cỡ "0.6"–"1.6" (server trả chuỗi)
    // Flash sale (đếm ngược)
    var flashEnabled: Bool? = nil
    var flashProductId: Int? = nil
    var flashEnd: Int? = nil         // epoch giây
    var flashDiscount: Int? = nil    // %
    var flashTitle: String? = nil
    // Hero section (banner chính đầu trang)
    var heroTitle: String? = nil     // tiêu đề lớn (nil = dùng slogan hoặc mặc định)
    var heroSubtitle: String? = nil  // dòng phụ (nil = mặc định)
    var heroEffect: String? = nil    // rainbow|gradient|gold|neon|glow|accent|none
    var heroFont: String? = nil      // font cho tiêu đề hero
    var heroAnim: String? = nil      // shimmer|wave|pulse|none
    // Slogan / dòng giới thiệu — thêm hiệu ứng màu & chuyển động
    var sloganEffect: String? = nil  // rainbow|gradient|gold|neon|glow|accent|none
    var sloganAnim: String? = nil    // shimmer|wave|pulse|none
    // Khuyến mãi (banner ảnh trong phần ví nạp tiền)
    var promoImageUrl: String? = nil
    var promoProductId: Int? = nil
    // 3 ô thống kê: số ẢO admin đặt + số THẬT đếm từ server (hiển thị = ảo + thật)
    var statUsersBase: Int? = nil
    var statSoldBase: Int? = nil
    var statReviewsBase: Int? = nil
    var statUsersReal: Int? = nil
    var statSoldReal: Int? = nil
    var statReviewsReal: Int? = nil
    // Thanh thông báo chạy đầu trang
    var announceEnabled: Bool? = nil
    var announceText: String? = nil
    var announceColor: String? = nil  // accent|red|green|gold|purple
    // Số sản phẩm tối đa mỗi danh mục ở lưới "Danh mục Game"
    var gamecatLimit: Int? = nil
}


// ---- Trang chủ cửa hàng (showcase): giao dịch / nạp / xếp hạng ----
struct ShowcaseOrder: Decodable, Hashable, Identifiable {
    var id: String { "\(user)-\(product)-\(at)-\(amount)" }
    let user: String
    let product: String
    let label: String
    let amount: Int
    let at: Int
}
struct ShowcaseTopup: Decodable, Hashable, Identifiable {
    var id: String { "\(user)-\(at)-\(amount)" }
    let user: String
    let amount: Int
    let at: Int
}
struct ShowcaseLeader: Decodable, Hashable, Identifiable {
    var id: Int { rank }
    let rank: Int
    let user: String
    let total: Int
}
struct StoreShowcase: Decodable, Equatable {
    let recentOrders: [ShowcaseOrder]
    let recentTopups: [ShowcaseTopup]
    let leaderboard: [ShowcaseLeader]
}

// Tất cả sản phẩm gom theo danh mục (1 request, tránh N+1)
struct StoreAllProducts: Decodable {
    let byCategory: [String: [StoreProduct]]
}

struct MediaUploadResponse: Decodable { let id: Int; let path: String }

// ---- Ví cửa hàng ----
struct StoreWalletTx: Identifiable, Decodable, Hashable {
    var id: String { "\(kind)-\(createdAt ?? 0)-\(amount)" }
    let kind: String      // topup | purchase
    let amount: Int
    let note: String
    let createdAt: Int?
}

struct StoreWallet: Decodable {
    let balance: Int
    let bonusPercent: Int
    let tx: [StoreWalletTx]
}

struct StoreTopupResponse: Decodable {
    let topupId: Int
    let ref: String
    let amount: Int
    let bonus: Int
    let credited: Int
    let bonusPercent: Int
    let message: String
    let bankInfo: BankInfo
    let qrUrl: String?
}

struct StoreBuyResponse: Decodable {
    let ok: Bool
    let owned: Bool
    let orderId: Int
    let key: String
    let productName: String
    let downloadUrl: String?
    let downloadFileId: Int?
    let balance: Int
    let message: String
}

struct StoreDownloadItem: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let kind: String?
    let media: [StoreMedia]
    let downloadUrl: String
    let hasFile: Bool
}

struct StoreTopupBonus: Decodable { let percent: Int }

// ---- Liên hệ admin & Nhóm cộng đồng (mạng xã hội) ----
struct SocialLink: Identifiable, Decodable, Hashable {
    var id: String { platform }
    let platform: String
    let url: String
    let enabled: Bool
}

struct StoreContacts: Decodable, Equatable {
    let contact: [SocialLink]
    let groups: [SocialLink]
}

struct StoreCategory: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let media: [StoreMedia]
}

struct StoreFolder: Identifiable, Decodable, Hashable {
    let id: Int
    let categoryId: Int
    let name: String
    let media: [StoreMedia]
}

struct StorePrice: Identifiable, Decodable, Hashable {
    let id: Int
    let label: String
    let amount: Int
    let available: Int?   // tồn kho riêng của mốc thời hạn này (nil = cũ/không rõ)

    var inStock: Bool { (available ?? 1) > 0 }
}

struct StoreProduct: Identifiable, Decodable, Hashable {
    let id: Int
    let folderId: Int
    let name: String
    let description: String
    let media: [StoreMedia]
    let prices: [StorePrice]
    let availableKeys: Int
    let hasDownload: Bool
    let kind: String?   // "app" (key/ứng dụng) | "acc" (acc game)

    var isAcc: Bool { (kind ?? "app") == "acc" }
    /// Nhãn cho phần "key/acc" tuỳ loại sản phẩm
    var itemLabel: String { isAcc ? "Tài khoản" : "KEY" }
    var stockLabel: String { isAcc ? "acc" : "key" }
}

struct StoreProductMine: Decodable, Hashable {
    let owned: Bool
    let key: String?
    let downloadUrl: String?
    let downloadFileId: Int?
}

struct StoreOrderCreateResponse: Decodable {
    let orderId: Int
    let ref: String
    let amount: Int
    let label: String
    let productName: String
    let message: String
    let bankInfo: BankInfo
    let qrUrl: String?
}

struct StoreOrder: Identifiable, Decodable, Hashable {
    let id: Int
    let productId: Int
    let productName: String
    let amount: Int
    let status: String
    let ref: String?
    let createdAt: Int?
    let key: String?
    let downloadUrl: String?
    let downloadFileId: Int?
}

struct StoreKeyItem: Identifiable, Decodable, Hashable {
    let id: Int
    let keyText: String
    let status: String
    let soldAt: Int?
    let priceId: Int?   // mốc thời hạn key thuộc về (nil = dùng chung)
}

struct StoreKeysInfo: Decodable {
    let available: Int
    let total: Int
    let keys: [StoreKeyItem]
}

struct StoreInventoryItem: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let kind: String?
    let folderName: String
    let categoryName: String
    let available: Int
    let sold: Int
}

struct StoreInventory: Decodable {
    let totalAvailable: Int
    let totalSold: Int
    let outOfStock: Int
    let products: [StoreInventoryItem]
}

struct StoreAdminOrder: Identifiable, Decodable, Hashable {
    let id: Int
    let amount: Int
    let status: String
    let ref: String?
    let createdAt: Int?
    let productName: String
    let username: String
}

struct IdResponse: Decodable { let message: String; let id: Int? }

// ---- Admin thống kê ----
// Decode "khoan dung": thiếu trường nào thì mặc định 0 / [] để không bao giờ
// bị kẹt ở màn "Đang tải thống kê..." khi server trả về thiếu trường.
struct AdminStats: Decodable {
    let totalUsers: Int
    let newUsers7d: Int
    let totalConversations: Int
    let totalMessages: Int
    let revenueTotal: Int
    let revenue30d: Int
    let totalFiles: Int
    let topProviders: [ProviderStat]

    enum CodingKeys: String, CodingKey {
        case totalUsers, newUsers7d, totalConversations, totalMessages
        case revenueTotal, revenue30d, totalFiles, topProviders
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalUsers = (try? c.decode(Int.self, forKey: .totalUsers)) ?? 0
        newUsers7d = (try? c.decode(Int.self, forKey: .newUsers7d)) ?? 0
        totalConversations = (try? c.decode(Int.self, forKey: .totalConversations)) ?? 0
        totalMessages = (try? c.decode(Int.self, forKey: .totalMessages)) ?? 0
        revenueTotal = (try? c.decode(Int.self, forKey: .revenueTotal)) ?? 0
        revenue30d = (try? c.decode(Int.self, forKey: .revenue30d)) ?? 0
        totalFiles = (try? c.decode(Int.self, forKey: .totalFiles)) ?? 0
        topProviders = (try? c.decode([ProviderStat].self, forKey: .topProviders)) ?? []
    }
}

struct ProviderStat: Decodable, Hashable {
    let provider: String
    let count: Int
}

// ---- Admin API key quản lý ----
struct AdminKeyInfo: Identifiable, Decodable, Hashable {
    var id: String { provider }
    let provider: String
    let configured: Bool
}

// ---- Xuất mã zip ----
struct ZipResponse: Decodable {
    let zipBase64: String
    let filename: String
    let fileCount: Int
}

// ---- Phân hệ mạng xã hội ----
struct SocialGenResponse: Decodable {
    let content: String
}
struct SocialDownloadResponse: Decodable {
    let fileId: Int
    let filename: String
    let size: Int
}

struct StreamKeyResponse: Decodable {
    let rtmpUrl: String
    let streamKey: String
    let title: String?
}

// TikTok Live (đọc bình luận tự động)
struct TikTokLiveStatus: Decodable {
    let ok: Bool?
    let status: String
    let username: String?
}

struct TikTokLiveEvent: Decodable, Identifiable {
    let id: Int
    let type: String      // join | gift | comment | follow | share
    let name: String
    let content: String
}

struct TikTokLiveEventsResponse: Decodable {
    let status: String
    let error: String?
    let events: [TikTokLiveEvent]
    let last: Int
}

struct TranslateResponse: Decodable {
    let text: String
    let source: String?
}

// KENIOS AI — API key cấp cho người khác
struct ApiTokenCreateResponse: Decodable { let token: String }
struct ApiTokenItem: Decodable, Identifiable {
    var id: String { token }
    let token: String
    let name: String?
    let calls: Int?
    let createdAt: Int?
}
struct ApiTokenListResponse: Decodable { let tokens: [ApiTokenItem] }

// Thiết bị đăng ký (UDID) cho phân phối ad-hoc
struct DeviceItem: Decodable, Identifiable {
    var id: String { udid }
    let udid: String
    let product: String?
    let version: String?
    let serial: String?
    let name: String?
    let createdAt: Int?
}
struct DevicesResponse: Decodable { let devices: [DeviceItem] }

// OTP — mã xác nhận email
struct OtpSendResponse: Decodable {
    let sent: Bool
    let channel: String       // internal | external | none
    let hint: String?
    let debugCode: String?
}

struct EncryptResponse: Decodable {
    let result: String
}

struct BinaryAnalysisResponse: Decodable {
    let fileType: String
    let entryPoint: String?
    let architecture: String?
    let sections: [String]?
    let strings: [String]?
    let hexDump: String
}

struct AsmResponse: Decodable {
    let result: String
}

struct SSHResultResponse: Decodable {
    let stdout: String
    let stderr: String
    let exitCode: Int
}

struct HTTPTestResponse: Decodable {
    let status: Int
    let headers: [String: String]
    let body: String
}

struct SQLResultResponse: Decodable {
    let columns: [String]
    let rows: [[String]]
    let message: String?
}

struct CleanupResponse: Decodable {
    let deletedMessages: Int
    let deletedConversations: Int
    let freedSpace: String
    let message: String
}

struct UserSearchResult: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String
    let publicId: String?
    let phone: String?
}

// Video feed (TikTok của riêng app)
struct PostItem: Identifiable, Decodable, Hashable {
    let id: Int
    let caption: String?
    var likes: Int
    let createdAt: Int?
    let fileId: Int
    let userId: Int?
    let username: String
    let publicId: String?
    let name: String?
    let mime: String?
    var liked: Bool
    var following: Bool?
    var views: Int?
    var comments: Int?
    var shares: Int?
    let isPublic: Bool?
    let avatarUrl: String?
}

struct PostComment: Identifiable, Decodable, Hashable {
    let id: Int
    let userId: Int?
    let username: String
    let content: String
    let createdAt: Int?
}

struct FollowResponse: Decodable { let following: Bool }
struct UserProfile: Decodable {
    let id: Int
    let username: String
    let publicId: String?
    let followers: Int
    let following: Int
    let posts: Int
    let isFollowing: Bool
    let totalLikes: Int?
    let avatarUrl: String?
    let bio: String?
}

struct PostCreateResponse: Decodable { let id: Int; let message: String }
struct LikeResponse: Decodable { let liked: Bool; let likes: Int }
struct LikesResponse: Decodable { let likes: Int }

// Live (phòng live + bình luận)
struct LiveRoom: Identifiable, Decodable, Hashable {
    let id: Int
    let title: String?
    let hlsUrl: String?
    let streamKey: String?
    let rtmpUrl: String?
    let viewers: Int
    let likes: Int
    let active: Int?
    let hostId: Int?
    let username: String
    let publicId: String?
    let createdAt: Int?
}
struct LiveComment: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String?
    let content: String
    let createdAt: Int?
}
struct LiveCreateResponse: Decodable {
    let id: Int
    let message: String
    let hlsUrl: String?
    let rtmpUrl: String?
    let streamKey: String?
}

// Trạng thái app (bảo trì)
struct AppStatus: Decodable {
    let maintenance: Bool
    let message: String
    let version: String?
}

struct FriendRequestItem: Identifiable, Decodable, Hashable {
    let id: Int
    let senderId: Int
    let senderName: String
    let receiverId: Int
    let receiverName: String
    let createdAt: Int
}

struct FriendItem: Identifiable, Decodable, Hashable {
    let id: Int
    let username: String
}

struct DirectMessageItem: Identifiable, Decodable, Hashable {
    let id: Int
    let senderId: Int
    let receiverId: Int
    let content: String
    let createdAt: Int
    let isRead: Int
}

// ---- Giỏ hàng ----
struct CartItem: Identifiable, Codable, Hashable {
    var id: UUID
    let productId: Int
    let productName: String
    let priceId: Int?
    let priceAmount: Int
    let priceLabel: String

    init(productId: Int, productName: String, priceId: Int?, priceAmount: Int, priceLabel: String) {
        self.id = UUID()
        self.productId = productId
        self.productName = productName
        self.priceId = priceId
        self.priceAmount = priceAmount
        self.priceLabel = priceLabel
    }
}

// ---- Mã khuyến mãi ----
struct PromoCode: Identifiable, Decodable, Hashable {
    let id: Int
    let code: String
    let discountType: String
    let discountValue: Int
    let minAmount: Int
    let maxUses: Int
    let usedCount: Int
    let expiresAt: Int
    let isActive: Int
    let createdAt: Int
}

struct PromoValidateResult: Decodable {
    let valid: Bool
    let discount: Int
    let label: String
    let discountType: String
    let discountValue: Int
}

// ---- Push Notification ----
struct PushSendResult: Decodable {
    let sent: Int
    let failed: Int
    let message: String
}

struct PushDeviceStats: Decodable {
    let totalDevices: Int
    let totalUsers: Int
}

