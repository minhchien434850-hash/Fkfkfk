import SwiftUI

// ============================ Mạng xã hội: danh mục nền tảng ============================
struct SocialPlatform: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

let kSocialPlatforms: [SocialPlatform] = [
    .init(id: "telegram",  label: "Telegram",  icon: "paperplane.fill",                 color: .blue),
    .init(id: "zalo",      label: "Zalo",      icon: "message.fill",                    color: .cyan),
    .init(id: "facebook",  label: "Facebook",  icon: "f.square.fill",                   color: .blue),
    .init(id: "messenger", label: "Messenger", icon: "ellipsis.message.fill",           color: .purple),
    .init(id: "instagram", label: "Instagram", icon: "camera.fill",                     color: .pink),
    .init(id: "tiktok",    label: "TikTok",    icon: "music.note",                      color: .primary),
    .init(id: "youtube",   label: "YouTube",   icon: "play.rectangle.fill",             color: .red),
    .init(id: "discord",   label: "Discord",   icon: "bubble.left.and.bubble.right.fill", color: .indigo),
    .init(id: "whatsapp",  label: "WhatsApp",  icon: "phone.circle.fill",               color: .green),
    .init(id: "phone",     label: "Điện thoại", icon: "phone.fill",                     color: .green),
    .init(id: "email",     label: "Email",     icon: "envelope.fill",                   color: .orange),
    .init(id: "website",   label: "Website",   icon: "globe",                           color: .teal),
]

func socialPlatform(_ id: String) -> SocialPlatform {
    kSocialPlatforms.first { $0.id == id }
        ?? SocialPlatform(id: id, label: id.capitalized, icon: "link", color: .accentColor)
}

func socialOpenURL(_ platform: String, _ raw: String) -> URL? {
    let s = raw.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return nil }
    switch platform {
    case "phone": return URL(string: "tel:" + s.filter { $0.isNumber || $0 == "+" })
    case "email": return URL(string: s.contains("@") ? "mailto:\(s)" : s)
    default:
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: "https://\(s)")
    }
}

// ============================ Khách: khối Liên hệ admin & Nhóm ============================
struct StoreContactsBlock: View {
    let contacts: StoreContacts

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !contacts.contact.isEmpty {
                group("Liên hệ admin", icon: "headphones", links: contacts.contact)
            }
            if !contacts.groups.isEmpty {
                group("Nhóm cộng đồng", icon: "person.3.fill", links: contacts.groups)
            }
        }
    }

    private func group(_ title: String, icon: String, links: [SocialLink]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(links) { link in
                        let p = socialPlatform(link.platform)
                        if let url = socialOpenURL(link.platform, link.url) {
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: p.icon).foregroundStyle(p.color)
                                    Text(p.label).font(.caption.bold()).foregroundStyle(.primary)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
}

// ============================ Admin: chỉnh sửa Liên hệ & Nhóm ============================
struct EditSocial: Identifiable, Hashable {
    let id = UUID()
    let platform: String
    var url: String = ""
    var enabled: Bool = false
}

struct StoreContactsEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0      // 0 = Liên hệ admin, 1 = Nhóm cộng đồng
    @State private var contact: [EditSocial] = []
    @State private var groups: [EditSocial] = []
    @State private var message: String?
    @State private var isError = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Picker("Loại", selection: $tab) {
                    Text("Liên hệ admin").tag(0)
                    Text("Nhóm cộng đồng").tag(1)
                }.pickerStyle(.segmented)
                Text(tab == 0
                     ? "Liên kết để khách LIÊN HỆ trực tiếp với admin (tài khoản cá nhân)."
                     : "Liên kết NHÓM cộng đồng (group) cho khách tham gia. Khác với liên hệ admin nhưng cùng 1 chỗ.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Bật/tắt & dán link") {
                let rows = tab == 0 ? $contact : $groups
                ForEach(rows) { $row in
                    let p = socialPlatform(row.platform)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $row.enabled) {
                            Label(p.label, systemImage: p.icon).foregroundStyle(.primary)
                        }
                        if row.enabled {
                            TextField(placeholder(row.platform), text: $row.url)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.caption)
                        }
                    }
                }
            }

            Section { Button("Lưu") { Task { await save() } } }
            if let message { Text(message).font(.footnote).foregroundStyle(isError ? .red : .green) }
        }
        .navigationTitle("Liên hệ & Nhóm")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load(); loaded = true } }
    }

    private func placeholder(_ platform: String) -> String {
        switch platform {
        case "phone": return "Số điện thoại (vd 0901234567)"
        case "email": return "Email (vd shop@gmail.com)"
        case "zalo":  return "Link Zalo (vd https://zalo.me/0901234567)"
        default:      return "Dán link \(socialPlatform(platform).label)"
        }
    }

    private func merge(_ saved: [SocialLink]) -> [EditSocial] {
        kSocialPlatforms.map { p in
            if let s = saved.first(where: { $0.platform == p.id }) {
                return EditSocial(platform: p.id, url: s.url, enabled: s.enabled)
            }
            return EditSocial(platform: p.id)
        }
    }

    private func load() async {
        if let r = try? await store.api.adminGetContacts() {
            contact = merge(r.contact)
            groups = merge(r.groups)
        } else {
            contact = merge([]); groups = merge([])
        }
    }

    private func payload(_ rows: [EditSocial]) -> [[String: Any]] {
        rows.map { ["platform": $0.platform, "url": $0.url.trimmingCharacters(in: .whitespaces),
                    "enabled": $0.enabled] }
    }

    private func save() async {
        message = nil
        do {
            let r = try await store.api.adminSetContacts(contact: payload(contact), groups: payload(groups))
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}
