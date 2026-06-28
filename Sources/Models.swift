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
