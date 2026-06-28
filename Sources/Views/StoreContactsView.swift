import SwiftUI

// ============================ Mạng xã hội: danh mục nền tảng ============================
struct SocialPlatform: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

let kSocialPlatforms: [SocialPlatform] = [
    // ── Nhắn tin tức thì ──
    .init(id: "telegram",  label: "Telegram",    icon: "paperplane.fill",                   color: .blue),
    .init(id: "zalo",      label: "Zalo",         icon: "message.fill",                      color: .cyan),
    .init(id: "messenger", label: "Messenger",    icon: "ellipsis.message.fill",             color: .purple),
    .init(id: "whatsapp",  label: "WhatsApp",     icon: "phone.circle.fill",                 color: .green),
    .init(id: "viber",     label: "Viber",        icon: "phone.badge.waveform.fill",         color: Color(red: 0.47, green: 0.24, blue: 0.70)),
    .init(id: "line",      label: "LINE",         icon: "bubble.left.and.text.bubble.right.fill", color: Color(red: 0.10, green: 0.76, blue: 0.24)),
    .init(id: "signal",    label: "Signal",       icon: "lock.shield.fill",                  color: Color(red: 0.24, green: 0.56, blue: 0.96)),
    .init(id: "wechat",    label: "WeChat",       icon: "bubble.left.and.bubble.right.fill", color: Color(red: 0.07, green: 0.71, blue: 0.11)),
    .init(id: "kakao",     label: "KakaoTalk",    icon: "face.smiling.fill",                 color: Color(red: 0.98, green: 0.86, blue: 0.05)),
    .init(id: "skype",     label: "Skype",        icon: "video.circle.fill",                 color: Color(red: 0.01, green: 0.67, blue: 0.93)),
    // ── Mạng xã hội ──
    .init(id: "facebook",  label: "Facebook",     icon: "f.square.fill",                     color: Color(red: 0.23, green: 0.35, blue: 0.71)),
    .init(id: "instagram", label: "Instagram",    icon: "camera.fill",                       color: .pink),
    .init(id: "tiktok",    label: "TikTok",       icon: "music.note",                        color: .primary),
    .init(id: "youtube",   label: "YouTube",      icon: "play.rectangle.fill",               color: .red),
    .init(id: "twitter",   label: "X (Twitter)",  icon: "x.circle.fill",                     color: Color(red: 0.05, green: 0.05, blue: 0.05)),
    .init(id: "threads",   label: "Threads",      icon: "at.circle.fill",                    color: Color(red: 0.05, green: 0.05, blue: 0.05)),
    .init(id: "linkedin",  label: "LinkedIn",     icon: "briefcase.fill",                    color: Color(red: 0.05, green: 0.46, blue: 0.73)),
    .init(id: "discord",   label: "Discord",      icon: "headphones.circle.fill",            color: .indigo),
    .init(id: "snapchat",  label: "Snapchat",     icon: "camera.aperture",                   color: Color(red: 1.0,  green: 0.93, blue: 0.0)),
    .init(id: "pinterest", label: "Pinterest",    icon: "pin.circle.fill",                   color: Color(red: 0.91, green: 0.12, blue: 0.14)),
    .init(id: "reddit",    label: "Reddit",       icon: "chart.bar.fill",                    color: Color(red: 1.0,  green: 0.36, blue: 0.0)),
    // ── Liên hệ trực tiếp ──
    .init(id: "phone",     label: "Điện thoại",   icon: "phone.fill",                        color: .green),
    .init(id: "email",     label: "Email",        icon: "envelope.fill",                     color: .orange),
    .init(id: "website",   label: "Website",      icon: "globe",                             color: .teal),
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

    private var enabledContacts: [SocialLink] {
        contacts.contact.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var enabledGroups: [SocialLink] {
        contacts.groups.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        if !enabledContacts.isEmpty || !enabledGroups.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Header label
                Label("Liên hệ & Cộng đồng", systemImage: "bubble.left.and.text.bubble.right.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                // Admin contact pills (horizontal scroll)
                if !enabledContacts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(enabledContacts.enumerated()), id: \.offset) { _, link in
                                let p = socialPlatform(link.platform)
                                if let url = socialOpenURL(link.platform, link.url) {
                                    Link(destination: url) {
                                        HStack(spacing: 5) {
                                            Image(systemName: p.icon)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(p.color)
                                            Text(p.label)
                                                .font(.caption.bold())
                                                .foregroundStyle(.primary)
                                        }
                                        .padding(.horizontal, 11)
                                        .padding(.vertical, 7)
                                        .background(Color(.tertiarySystemBackground))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }

                // Group buttons (max 4, 2 per row)
                if !enabledGroups.isEmpty {
                    let rows = stride(from: 0, to: enabledGroups.count, by: 2).map {
                        Array(enabledGroups[$0..<min($0 + 2, enabledGroups.count)])
                    }
                    VStack(spacing: 8) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 8) {
                                ForEach(Array(row.enumerated()), id: \.offset) { _, link in
                                    let p = socialPlatform(link.platform)
                                    if let url = socialOpenURL(link.platform, link.url) {
                                        Link(destination: url) {
                                            HStack(spacing: 5) {
                                                Image(systemName: "person.3.fill")
                                                    .font(.system(size: 10))
                                                Image(systemName: p.icon)
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(p.color)
                                                Text("Nhóm \(p.label)")
                                                    .font(.caption.bold())
                                                    .lineLimit(1)
                                            }
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 9)
                                            .background(p.color.opacity(0.13))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                                // Fill empty slot if odd number of groups in a row
                                if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

// ============================ Khách: sheet Liên hệ & Nhóm (mở khi bấm icon header) ============================
struct StoreContactsSheet: View {
    let contacts: StoreContacts
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private var enabledContacts: [SocialLink] {
        contacts.contact.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var enabledGroups: [SocialLink] {
        contacts.groups.filter { $0.enabled && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Liên hệ admin").tag(0)
                    Text("Nhóm cộng đồng").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                if tab == 0 {
                    contactList(enabledContacts, isGroup: false)
                } else {
                    contactList(enabledGroups, isGroup: true)
                }
            }
            .navigationTitle(tab == 0 ? "Liên hệ admin" : "Nhóm cộng đồng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func contactList(_ links: [SocialLink], isGroup: Bool) -> some View {
        if links.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: isGroup ? "person.3" : "person.crop.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                Text(isGroup ? "Chưa có nhóm cộng đồng nào." : "Chưa có liên hệ admin nào.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            List {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    let p = socialPlatform(link.platform)
                    if let url = socialOpenURL(link.platform, link.url) {
                        Link(destination: url) {
                            HStack(spacing: 14) {
                                Image(systemName: p.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(p.color)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(isGroup ? "Nhóm \(p.label)" : p.label)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(link.url.trimmingCharacters(in: .whitespaces))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// ============================ Admin: chỉnh sửa Liên hệ & Nhóm ============================
struct EditSocial: Identifiable, Hashable {
    let id = UUID()
    var platform: String   // var để có thể dùng Picker binding
    var url: String = ""
    var enabled: Bool = false
}

struct StoreContactsEditor: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0          // 0 = Liên hệ admin, 1 = Nhóm cộng đồng
    @State private var contact: [EditSocial] = []
    @State private var groupList: [EditSocial] = []   // cùng cấu trúc như contact
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
                     ? "Hiển thị các nút liên hệ TRỰC TIẾP với admin. Bật nền tảng nào, dán link tương ứng."
                     : "Bật nền tảng nào, dán link NHÓM tương ứng. Khách bấm vào để vào nhóm.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Cả hai tab dùng cùng một layout: danh sách đầy đủ nền tảng + toggle + link
            Section("Bật/tắt & dán link") {
                ForEach(tab == 0 ? $contact : $groupList) { $row in
                    let p = socialPlatform(row.platform)
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $row.enabled) {
                            Label(p.label, systemImage: p.icon).foregroundStyle(.primary)
                        }
                        if row.enabled {
                            TextField(contactPlaceholder(row.platform), text: $row.url)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.caption)
                        }
                    }
                }
            }

            Section { Button("Lưu thay đổi") { Task { await save() } } }
            if let message {
                Text(message).font(.footnote).foregroundStyle(isError ? .red : .green)
            }
        }
        .navigationTitle("Liên hệ & Nhóm")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { await load(); loaded = true } }
    }

    private func contactPlaceholder(_ platform: String) -> String {
        switch platform {
        case "phone":     return "Số điện thoại (vd 0901234567)"
        case "email":     return "Email (vd shop@gmail.com)"
        case "zalo":      return "Link Zalo (vd https://zalo.me/0901234567)"
        case "website":   return "URL website (vd https://kenios.app)"
        case "telegram":  return "Link Telegram (vd https://t.me/username)"
        case "messenger": return "Link Messenger (vd https://m.me/username)"
        case "whatsapp":  return "Số WhatsApp hoặc link (vd https://wa.me/84901234567)"
        case "viber":     return "Số Viber hoặc link (vd https://viber.com/username)"
        case "line":      return "Link LINE (vd https://line.me/ti/p/username)"
        case "signal":    return "Link Signal (vd https://signal.me/#p/+84...)"
        case "wechat":    return "ID WeChat (vd username)"
        case "kakao":     return "Link KakaoTalk (vd https://open.kakao.com/...)"
        case "skype":     return "ID Skype (vd live:username)"
        case "facebook":  return "Link Facebook (vd https://fb.com/username)"
        case "instagram": return "Link Instagram (vd https://instagram.com/username)"
        case "tiktok":    return "Link TikTok (vd https://tiktok.com/@username)"
        case "youtube":   return "Link YouTube (vd https://youtube.com/c/channel)"
        case "twitter":   return "Link X/Twitter (vd https://x.com/username)"
        case "threads":   return "Link Threads (vd https://threads.net/@username)"
        case "linkedin":  return "Link LinkedIn (vd https://linkedin.com/in/name)"
        case "discord":   return "Link Discord (vd https://discord.gg/invite)"
        case "snapchat":  return "Link Snapchat (vd https://snapchat.com/add/name)"
        case "pinterest": return "Link Pinterest (vd https://pinterest.com/username)"
        case "reddit":    return "Link Reddit (vd https://reddit.com/u/username)"
        default:          return "Dán link \(socialPlatform(platform).label)"
        }
    }

    private func merge(_ saved: [SocialLink]) -> [EditSocial] {
        kSocialPlatforms.map { sp in
            if let s = saved.first(where: { $0.platform == sp.id }) {
                return EditSocial(platform: sp.id, url: s.url, enabled: s.enabled)
            }
            return EditSocial(platform: sp.id)
        }
    }

    private func load() async {
        if let r = try? await store.api.adminGetContacts() {
            contact   = merge(r.contact)
            groupList = merge(r.groups)
        } else {
            contact   = merge([])
            groupList = merge([])
        }
    }

    private func socialPayload(_ rows: [EditSocial]) -> [[String: Any]] {
        rows.map { ["platform": $0.platform,
                    "url": $0.url.trimmingCharacters(in: .whitespaces),
                    "enabled": $0.enabled] }
    }

    private func save() async {
        message = nil
        do {
            let r = try await store.api.adminSetContacts(
                contact: socialPayload(contact),
                groups: socialPayload(groupList))
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}
