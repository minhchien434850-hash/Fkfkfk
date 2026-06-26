import SwiftUI

// ============================ Mạng xã hội: danh mục nền tảng ============================
struct SocialPlatform: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
}

let kSocialPlatforms: [SocialPlatform] = [
    .init(id: "telegram",  label: "Telegram",   icon: "paperplane.fill",                  color: .blue),
    .init(id: "zalo",      label: "Zalo",        icon: "message.fill",                     color: .cyan),
    .init(id: "facebook",  label: "Facebook",    icon: "f.square.fill",                    color: Color(red: 0.23, green: 0.35, blue: 0.71)),
    .init(id: "messenger", label: "Messenger",   icon: "ellipsis.message.fill",            color: .purple),
    .init(id: "instagram", label: "Instagram",   icon: "camera.fill",                      color: .pink),
    .init(id: "tiktok",    label: "TikTok",      icon: "music.note",                       color: .primary),
    .init(id: "youtube",   label: "YouTube",     icon: "play.rectangle.fill",              color: .red),
    .init(id: "discord",   label: "Discord",     icon: "bubble.left.and.bubble.right.fill", color: .indigo),
    .init(id: "whatsapp",  label: "WhatsApp",    icon: "phone.circle.fill",                color: .green),
    .init(id: "phone",     label: "Điện thoại",  icon: "phone.fill",                       color: .green),
    .init(id: "email",     label: "Email",       icon: "envelope.fill",                    color: .orange),
    .init(id: "website",   label: "Website",     icon: "globe",                            color: .teal),
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

                // Group buttons (max 2, side by side)
                if !enabledGroups.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(enabledGroups.prefix(2).enumerated()), id: \.offset) { i, link in
                            let p = socialPlatform(link.platform)
                            if let url = socialOpenURL(link.platform, link.url) {
                                Link(destination: url) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 10))
                                        Image(systemName: p.icon)
                                            .font(.system(size: 11))
                                            .foregroundStyle(p.color)
                                        Text("Nhóm \(i + 1) \(p.label)")
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
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
    @State private var tab = 0       // 0 = Liên hệ admin, 1 = Nhóm cộng đồng
    @State private var contact: [EditSocial] = []
    @State private var group1 = EditSocial(platform: "telegram")
    @State private var group2 = EditSocial(platform: "zalo")
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
                     ? "Hiển thị các nút liên hệ TRỰC TIẾP với admin. Khách bấm để mở Zalo/Telegram/... của bạn."
                     : "2 nút nhóm cộng đồng nằm cạnh nhau ở dưới cửa hàng. Chọn nền tảng & dán link nhóm.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if tab == 0 {
                // Liên hệ admin — danh sách tất cả platform
                Section("Bật/tắt & dán link liên hệ") {
                    ForEach($contact) { $row in
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
            } else {
                // Nhóm cộng đồng — 2 slot cố định
                groupSection(title: "Nút Nhóm 1", social: $group1)
                groupSection(title: "Nút Nhóm 2", social: $group2)

                Section {
                    Label("Preview — nút sẽ hiển thị thế này trong cửa hàng:", systemImage: "eye")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        groupPreviewButton(group1)
                        groupPreviewButton(group2)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
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

    @ViewBuilder
    private func groupSection(title: String, social: Binding<EditSocial>) -> some View {
        let p = socialPlatform(social.wrappedValue.platform)
        Section(title) {
            Toggle("Hiển thị nút này", isOn: social.enabled)
            if social.wrappedValue.enabled {
                Picker("Nền tảng", selection: social.platform) {
                    ForEach(kSocialPlatforms) { sp in
                        Label(sp.label, systemImage: sp.icon).tag(sp.id)
                    }
                }
                TextField(contactPlaceholder(social.wrappedValue.platform), text: social.url)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            _ = p  // reference to avoid unused-variable warning
        }
    }

    @ViewBuilder
    private func groupPreviewButton(_ s: EditSocial) -> some View {
        if s.enabled {
            let p = socialPlatform(s.platform)
            HStack(spacing: 5) {
                Image(systemName: "person.3.fill").font(.caption2)
                Image(systemName: p.icon).font(.caption2).foregroundStyle(p.color)
                Text("Nhóm \(p.label)").font(.caption.bold()).lineLimit(1)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(p.color.opacity(0.13))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 36)
        }
    }

    private func contactPlaceholder(_ platform: String) -> String {
        switch platform {
        case "phone":    return "Số điện thoại (vd 0901234567)"
        case "email":    return "Email (vd shop@gmail.com)"
        case "zalo":     return "Link Zalo (vd https://zalo.me/0901234567)"
        case "website":  return "URL website (vd https://kenios.app)"
        default:         return "Dán link \(socialPlatform(platform).label)"
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
            contact = merge(r.contact)
            if r.groups.indices.contains(0) {
                let g = r.groups[0]
                group1 = EditSocial(platform: g.platform, url: g.url, enabled: g.enabled)
            }
            if r.groups.indices.contains(1) {
                let g = r.groups[1]
                group2 = EditSocial(platform: g.platform, url: g.url, enabled: g.enabled)
            }
        } else {
            contact = merge([])
        }
    }

    private func contactPayload(_ rows: [EditSocial]) -> [[String: Any]] {
        rows.map { ["platform": $0.platform, "url": $0.url.trimmingCharacters(in: .whitespaces),
                    "enabled": $0.enabled] }
    }

    private func save() async {
        message = nil
        let groupsPayload: [[String: Any]] = [
            ["platform": group1.platform, "url": group1.url.trimmingCharacters(in: .whitespaces), "enabled": group1.enabled],
            ["platform": group2.platform, "url": group2.url.trimmingCharacters(in: .whitespaces), "enabled": group2.enabled],
        ]
        do {
            let r = try await store.api.adminSetContacts(
                contact: contactPayload(contact), groups: groupsPayload)
            isError = false; message = r.message
        } catch { isError = true; message = error.localizedDescription }
    }
}
