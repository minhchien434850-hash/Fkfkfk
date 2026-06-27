import SwiftUI
import WebKit
import PhotosUI

// ============================ Messenger Hub ============================
// Tab 0 — Thủ công: copy clipboard + mở app (paste & gửi tay)
// Tab 1 — Tự động:  WKWebView + JavaScript inject (gửi thẳng)
// Cả hai dùng chung bộ soạn thảo tin nhắn (mỗi dòng = 1 tin)

// MARK: - Shared message storage key
private let kMsgLinesKey = "messengerLines"

// ─────────────────────────────────────────────
// MARK: - Manual platforms (URL scheme)
// ─────────────────────────────────────────────
private struct ManualPlatform: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let urlScheme: (String, String) -> String
}

private let kManualPlatforms: [ManualPlatform] = [
    .init(id: "telegram",  label: "Telegram",  icon: "paperplane.fill",
          color: .blue) { rec, _ in
        let u = rec.hasPrefix("@") ? String(rec.dropFirst()) : rec
        return "tg://resolve?domain=\(u)"
    },
    .init(id: "zalo",      label: "Zalo",      icon: "message.fill",
          color: .cyan)      { _, _ in "zalo://" },
    .init(id: "whatsapp",  label: "WhatsApp",  icon: "phone.circle.fill",
          color: .green) { rec, txt in
        let p = rec.filter { $0.isNumber || $0 == "+" }
        return "whatsapp://send?phone=\(p)&text=\(txt)"
    },
    .init(id: "messenger", label: "Messenger", icon: "ellipsis.message.fill",
          color: .purple)    { _, _ in "fb-messenger://" },
    .init(id: "imessage",  label: "iMessage",  icon: "bubble.left.fill",
          color: Color(red: 0.1, green: 0.75, blue: 0.1)) { rec, txt in
        "sms:\(rec)&body=\(txt)"
    },
    .init(id: "viber",     label: "Viber",     icon: "phone.fill",
          color: .indigo) { rec, _ in
        "viber://chat?number=\(rec.filter { $0.isNumber || $0 == "+" })"
    },
]

// ─────────────────────────────────────────────
// MARK: - Auto / Web platforms
// ─────────────────────────────────────────────
private enum AutoWebPlatform: String, CaseIterable {
    case telegram = "telegram"
    case whatsapp = "whatsapp"
    case zalo     = "zalo"
    case messenger = "messenger"
    case instagram = "instagram"

    var label: String {
        switch self {
        case .telegram:  return "Telegram"
        case .whatsapp:  return "WhatsApp"
        case .zalo:      return "Zalo"
        case .messenger: return "Messenger"
        case .instagram: return "Instagram"
        }
    }
    var icon: String {
        switch self {
        case .telegram:  return "paperplane.fill"
        case .whatsapp:  return "phone.circle.fill"
        case .zalo:      return "message.fill"
        case .messenger: return "ellipsis.message.fill"
        case .instagram: return "camera.fill"
        }
    }
    var color: Color {
        switch self {
        case .telegram:  return .blue
        case .whatsapp:  return .green
        case .zalo:      return .cyan
        case .messenger: return .purple
        case .instagram: return .pink
        }
    }
    var homeURL: URL {
        switch self {
        case .telegram:  return URL(string: "https://web.telegram.org/k/")!
        case .whatsapp:  return URL(string: "https://web.whatsapp.com/")!
        case .zalo:      return URL(string: "https://chat.zalo.me/")!
        case .messenger: return URL(string: "https://www.messenger.com/")!
        case .instagram: return URL(string: "https://www.instagram.com/direct/inbox/")!
        }
    }
    var supportsAutoNav: Bool { self == .telegram || self == .whatsapp }
    var loginHint: String {
        switch self {
        case .telegram:  return "Quét QR bằng Telegram app"
        case .whatsapp:  return "Quét QR bằng WhatsApp → Thiết bị liên kết"
        case .zalo:      return "Quét QR bằng Zalo app"
        case .messenger: return "Đăng nhập tài khoản Facebook"
        case .instagram: return "Đăng nhập Instagram, điều hướng đến conversation"
        }
    }

    func chatURL(recipient: String) -> URL? {
        let r = recipient.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return nil }
        switch self {
        case .telegram:
            let u = r.hasPrefix("@") ? String(r.dropFirst()) : r
            return URL(string: "https://web.telegram.org/k/#@\(u)")
        case .whatsapp:
            let p = r.filter { $0.isNumber || $0 == "+" }
            return URL(string: "https://web.whatsapp.com/send?phone=\(p)")
        default: return nil
        }
    }

    // JS kiểm tra đã đăng nhập web chưa → trả 'in' nếu rồi
    var loginCheckJS: String {
        switch self {
        case .telegram:  return "(function(){return (document.querySelector('.chatlist, .chatlist-container, #column-left .chatlist'))?'in':'out';})();"
        case .whatsapp:  return "(function(){return document.querySelector('#pane-side')?'in':'out';})();"
        case .zalo:      return "(function(){return document.querySelector('.conv-list, [class*=\"conv-item\"], #conversation-list')?'in':'out';})();"
        case .messenger: return "(function(){return document.querySelector('[aria-label][role=\"navigation\"], a[href*=\"/t/\"]')?'in':'out';})();"
        case .instagram: return "(function(){return document.querySelector('div[role=\"list\"] a[href*=\"/direct/t/\"], a[href*=\"/direct/t/\"]')?'in':'out';})();"
        }
    }

    // JS đọc danh sách cuộc trò chuyện (tên hiển thị) → trả JSON mảng tên
    var chatListJS: String {
        let sel: String
        switch self {
        case .telegram:  sel = ".chatlist .peer-title, .chatlist .user-title, .chatlist-chat .peer-title"
        case .whatsapp:  sel = "#pane-side [role=\"listitem\"] span[title]"
        case .zalo:      sel = "[class*=\"conv-item\"] [class*=\"name\"], .conv-item .truncate"
        case .messenger: sel = "a[href*=\"/t/\"] span[dir=\"auto\"], a[href*=\"/t/\"]"
        case .instagram: sel = "div[role=\"list\"] a[href*=\"/direct/t/\"] span, a[href*=\"/direct/t/\"]"
        }
        return """
        (function(){
          var seen={},out=[];
          document.querySelectorAll('\(sel)').forEach(function(e){
            var t=(e.getAttribute('title')||e.textContent||'').trim();
            if(t&&t.length<=60&&!seen[t]){seen[t]=1;out.push(t);}
          });
          return JSON.stringify(out.slice(0,40));
        })();
        """
    }

    // JS mở đúng cuộc trò chuyện theo tên (click vào dòng chat khớp tên)
    func openChatJS(_ name: String) -> String {
        let esc = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(){
          var target='\(esc)';
          var rows=document.querySelectorAll('a,[role="listitem"],[class*="conv-item"],.chatlist-chat,.ListItem');
          for(var i=0;i<rows.length;i++){
            var t=(rows[i].getAttribute('title')||rows[i].textContent||'').trim();
            if(t.indexOf(target)>=0){
              var c=rows[i].querySelector('a')||rows[i];
              c.click();
              return 'ok';
            }
          }
          return 'not_found';
        })();
        """
    }

    func sendJS(_ message: String) -> String {
        let esc = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        switch self {
        case .telegram:
            return """
            (function(){
              var el=document.querySelector('.input-message-input[contenteditable]');
              if(!el)return 'not_found';
              el.focus();
              document.execCommand('selectAll',false,null);
              document.execCommand('insertText',false,'\(esc)');
              setTimeout(function(){
                var b=document.querySelector('.btn-send,.btn-icon.btn-send-message');
                if(b){b.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },400);return 'ok';
            })();
            """
        case .whatsapp:
            return """
            (function(){
              var el=document.querySelector('div[contenteditable="true"][data-tab]')
                   ||document.querySelector('[data-testid="conversation-compose-box-input"]');
              if(!el)return 'not_found';
              el.focus();
              document.execCommand('selectAll',false,null);
              document.execCommand('insertText',false,'\(esc)');
              setTimeout(function(){
                var b=document.querySelector('[data-testid="send"]')
                     ||document.querySelector('button[aria-label="Send"]')
                     ||document.querySelector('span[data-icon="send"]');
                if(b){b.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },500);return 'ok';
            })();
            """
        case .zalo:
            return """
            (function(){
              var el=document.querySelector('div[contenteditable="true"][placeholder]')
                   ||document.querySelector('div[contenteditable="true"].input-chat')
                   ||document.querySelector('div[contenteditable="true"]');
              if(!el)return 'not_found';
              el.focus();
              document.execCommand('selectAll',false,null);
              document.execCommand('insertText',false,'\(esc)');
              setTimeout(function(){
                var b=document.querySelector('button[type="submit"],.send-btn,[aria-label="Gửi"],[aria-label="Send"]');
                if(b){b.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },400);return 'ok';
            })();
            """
        case .messenger:
            return """
            (function(){
              var el=document.querySelector('div[aria-label="Message"]')
                   ||document.querySelector('div[role="textbox"][aria-multiline="true"]')
                   ||document.querySelector('div[contenteditable="true"][class*="notranslate"]');
              if(!el)return 'not_found';
              el.focus();
              document.execCommand('selectAll',false,null);
              document.execCommand('insertText',false,'\(esc)');
              setTimeout(function(){
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true,returnValue:true}));
              },400);return 'ok';
            })();
            """
        case .instagram:
            return """
            (function(){
              var el=document.querySelector('div[role="textbox"][aria-label]')
                   ||document.querySelector('textarea[placeholder]');
              if(!el)return 'not_found';
              el.focus();
              if(el.tagName==='TEXTAREA'){
                var s=Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype,'value').set;
                s.call(el,'\(esc)');
                el.dispatchEvent(new Event('input',{bubbles:true}));
              } else {
                document.execCommand('selectAll',false,null);
                document.execCommand('insertText',false,'\(esc)');
              }
              setTimeout(function(){
                var bs=document.querySelectorAll('button,[role="button"]');
                for(var b of bs){
                  var lbl=(b.getAttribute('aria-label')||'').toLowerCase();
                  var txt=(b.textContent||'').trim().toLowerCase();
                  if(lbl.includes('send')||txt==='send'||txt==='gửi'){b.click();return;}
                }
              },500);return 'ok';
            })();
            """
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Speed presets
// ─────────────────────────────────────────────
private enum SpeedPreset: String, CaseIterable {
    case slow   = "slow"
    case normal = "normal"
    case fast   = "fast"
    case turbo  = "turbo"

    var label: String {
        switch self {
        case .slow:   return "🐢 Chậm"
        case .normal: return "🚶 Vừa"
        case .fast:   return "🏃 Nhanh"
        case .turbo:  return "⚡ Turbo"
        }
    }
    var seconds: Int {
        switch self {
        case .slow:   return 30
        case .normal: return 15
        case .fast:   return 8
        case .turbo:  return 5
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - Persistent web views
// ─────────────────────────────────────────────
private final class HubWebViews {
    static let shared = HubWebViews()
    private var cache: [String: WKWebView] = [:]
    func view(for p: AutoWebPlatform) -> WKWebView {
        if let v = cache[p.rawValue] { return v }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        cache[p.rawValue] = wv
        return wv
    }
}

// ─────────────────────────────────────────────
// MARK: - MessengerHubView
// ─────────────────────────────────────────────
struct MessengerHubView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var initialTab: Int = 0

    // ── Shared ──────────────────────────────
    @AppStorage(kMsgLinesKey) private var rawLines = ""

    // ── Manual tab ──────────────────────────
    @AppStorage("mhManualPlatform") private var manualPlatformId = "telegram"
    @AppStorage("mhManualRecipient") private var manualRecipient = ""
    @AppStorage("mhManualDelay")    private var manualDelay = 10

    @State private var manRunning  = false
    @State private var manIdx      = 0
    @State private var manCountdown = 0
    @State private var manCopied   = ""
    @State private var manTask: Task<Void, Never>?

    // ── Auto tab ────────────────────────────
    @AppStorage("mhAutoPlatform")   private var autoPlatformRaw = "telegram"
    @AppStorage("mhAutoRecipient")  private var autoRecipient   = ""
    @AppStorage("mhAutoDelay")      private var autoDelay       = 15
    @AppStorage("mhAutoSpeed")      private var speedPresetRaw  = "normal"
    // Tốc độ tinh chỉnh 0.1 – 5.0 giây giữa các tin (ưu tiên dùng giá trị này)
    @AppStorage("mhAutoDelaySec")   private var autoDelaySec: Double = 1.0
    // Danh bạ người nhận đã lưu (mỗi dòng "Tên|định danh") — chọn nhanh, khỏi gõ lại
    @AppStorage("mhSavedRecipients") private var savedRecipientsRaw = ""

    @State private var autoRunning  = false
    @State private var autoIdx      = 0
    @State private var autoCountdown = 0
    @State private var autoStatuses: [HubSendState] = []
    @State private var autoTask: Task<Void, Never>?
    @State private var showWebLogin = false
    // Trạng thái kết nối web + danh sách bạn bè/cuộc trò chuyện đọc từ phiên web
    @State private var autoConnected = false
    @State private var autoFriends: [String] = []
    @State private var loadingFriends = false
    @State private var selectedFriend = ""
    // Zalo: nhắn từng thành viên nhóm
    @State private var zaloMembers: [String] = []
    @State private var scanningMembers = false
    @State private var blasting = false
    @State private var blastIdx = 0
    @State private var blastDone = 0
    @State private var blastTask: Task<Void, Never>?
    // Tab 3: Tool nhóm — gửi hàng loạt cho nhiều bạn đã chọn (Messenger / Zalo)
    @AppStorage("mhToolPlatform") private var toolPlatformRaw = "messenger"
    @State private var toolFriends: [String] = []
    @State private var toolSelected: Set<String> = []
    @State private var loadingTool = false
    @State private var toolConnected = false
    @State private var toolRunning = false
    @State private var toolDone = 0
    @State private var toolTask: Task<Void, Never>?
    @State private var toolImageItem: PhotosPickerItem?
    @State private var toolImageData: Data?

    // ── UI ──────────────────────────────────
    @State private var activeTab: Int = 0

    // Quy tắc: dòng kết thúc bằng đúng 1 dấu chấm (.) + xuống dòng = 1 tin nhắn.
    // "..." hoặc ".." ở cuối = KHÔNG tính. Dấu chấm giữa chữ không ảnh hưởng.
    private var messages: [String] {
        rawLines.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                guard !line.isEmpty, line.hasSuffix(".") else { return false }
                return !line.hasSuffix("..")   // loại "..." và ".."
            }
    }
    private var manualPlatform: ManualPlatform {
        kManualPlatforms.first { $0.id == manualPlatformId } ?? kManualPlatforms[0]
    }
    private var autoPlatform: AutoWebPlatform {
        AutoWebPlatform(rawValue: autoPlatformRaw) ?? .telegram
    }
    private var selectedSpeed: SpeedPreset {
        SpeedPreset(rawValue: speedPresetRaw) ?? .normal
    }

    // ── Danh bạ người nhận đã lưu ──
    struct SavedRecipient: Identifiable, Hashable { let id = UUID(); let name: String; let value: String }
    private var savedRecipients: [SavedRecipient] {
        savedRecipientsRaw.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: "|")
            let value = (parts.count > 1 ? parts[1] : parts[0]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return nil }
            let name = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespaces) : value
            return SavedRecipient(name: name.isEmpty ? value : name, value: value)
        }
    }
    private func saveRecipient(_ value: String) {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        var lines = savedRecipientsRaw.components(separatedBy: "\n").filter { !$0.isEmpty }
        if !lines.contains(where: { $0.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces) == v }) {
            lines.append(v)   // lưu dạng "định danh" (tên = chính nó)
            savedRecipientsRaw = lines.joined(separator: "\n")
        }
    }
    private func removeRecipient(_ r: SavedRecipient) {
        let lines = savedRecipientsRaw.components(separatedBy: "\n").filter {
            ($0.components(separatedBy: "|").last?.trimmingCharacters(in: .whitespaces) ?? $0) != r.value
        }
        savedRecipientsRaw = lines.joined(separator: "\n")
    }

    // Khối chọn người nhận đã lưu + nút lưu người nhận hiện tại (dùng cho cả 2 tab)
    @ViewBuilder private func recipientPicker(_ current: Binding<String>) -> some View {
        if !savedRecipients.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(savedRecipients) { r in
                        HStack(spacing: 4) {
                            Button {
                                current.wrappedValue = r.value
                            } label: {
                                Label(r.name, systemImage: "person.crop.circle")
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(current.wrappedValue == r.value
                                                ? store.accentColor.opacity(0.25)
                                                : Color(.tertiarySystemBackground))
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                            Button { removeRecipient(r) } label: {
                                Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        Button {
            saveRecipient(current.wrappedValue)
        } label: {
            Label("Lưu người nhận này vào danh bạ", systemImage: "person.badge.plus")
                .font(.caption)
        }
        .disabled(current.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Header
                Section {
                    KHeroHeader(
                        icon: activeTab == 0 ? "doc.on.clipboard.fill" : "bolt.horizontal.fill",
                        title: activeTab == 0 ? store.t("Nhắn tin thủ công", "Manual messaging") : store.t("Nhắn tin tự động", "Auto messaging"),
                        subtitle: activeTab == 0
                            ? store.t("Copy clipboard → paste & gửi trong app", "Copy to clipboard → paste & send in-app")
                            : store.t("Quét QR đăng nhập → gửi thẳng qua web", "Scan QR to log in → send directly via web"))
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Mode switcher
                Section {
                    Picker(store.t("Chế độ", "Mode"), selection: $activeTab) {
                        Text("📋 " + store.t("Thủ công", "Manual")).tag(0)
                        Text("⚡ " + store.t("Tự động", "Auto")).tag(1)
                        Text("👥 " + store.t("Tool nhóm", "Group tool")).tag(2)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: activeTab) { _ in
                        if manRunning { stopManual() }
                        if autoRunning { stopAuto() }
                        if toolRunning { stopTool() }
                    }
                }

                // ── Shared: Message Composer ──────────────
                Section {
                    TextEditor(text: $rawLines)
                        .frame(minHeight: 140)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                } header: {
                    HStack {
                        Label(store.t("Soạn thảo tin nhắn", "Compose messages"), systemImage: "square.and.pencil")
                        Spacer()
                        Text("\(messages.count) tin")
                            .font(.caption.bold())
                            .foregroundStyle(store.accentColor)
                    }
                } footer: {
                    Text("Dấu chấm (.) ở cuối dòng + xuống dòng = 1 tin nhắn. Dấu chấm giữa chữ không tính. Dấu \"...\" không tính.\nVí dụ:\nTôi là kenios.\nBạn tên là gì.")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Preview danh sách tin
                if !messages.isEmpty {
                    Section {
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, msg in
                            let isActive = activeTab == 0
                                ? (manRunning && i == manIdx)
                                : (autoRunning && i == autoIdx)
                            let isDone = activeTab == 0
                                ? (manRunning && i < manIdx)
                                : (i < autoStatuses.count && autoStatuses[i] == .ok)
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(isActive ? store.accentColor : Color(.tertiarySystemBackground))
                                        .frame(width: 22, height: 22)
                                    Text("\(i + 1)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(isActive ? .white : .secondary)
                                }
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(isDone ? .secondary : .primary)
                                    .strikethrough(isDone)
                                Spacer()
                                if isActive {
                                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.green)
                                } else if i < autoStatuses.count && autoStatuses[i] == .fail {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                                }
                            }
                        }
                    } header: {
                        Text("Xem trước \(messages.count) tin nhắn")
                    }
                }

                // ─────────────────── TAB: Thủ công ───────────────────
                if activeTab == 0 {
                    Section("Ứng dụng nhắn tin") {
                        Picker("Ứng dụng", selection: $manualPlatformId) {
                            ForEach(kManualPlatforms) { p in
                                Label(p.label, systemImage: p.icon).tag(p.id)
                            }
                        }
                        TextField(manualRecipientHint, text: $manualRecipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(manualPlatformId == "telegram" ? .default : .phonePad)
                        recipientPicker($manualRecipient)
                    }

                    Section {
                        Stepper(value: $manualDelay, in: 3...120) {
                            HStack {
                                Text("Khoảng cách mỗi tin")
                                Spacer()
                                Text("\(manualDelay) giây")
                                    .foregroundStyle(store.accentColor).font(.subheadline.bold())
                            }
                        }
                    } footer: {
                        Text("Sau \(manualDelay)s: tự copy tin tiếp theo + mở \(manualPlatform.label). Bạn paste → Gửi → quay lại.")
                            .font(.caption2)
                    }

                    // Trạng thái đang chạy
                    if manRunning {
                        Section {
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle().stroke(Color(.systemFill), lineWidth: 6).frame(width: 80, height: 80)
                                    Circle()
                                        .trim(from: 0, to: manCountdown > 0 ? CGFloat(manCountdown) / CGFloat(manualDelay) : 0)
                                        .stroke(store.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                        .frame(width: 80, height: 80)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 1), value: manCountdown)
                                    VStack(spacing: 2) {
                                        Text("\(manCountdown)").font(.title2.monospacedDigit().bold())
                                        Text("giây").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Tin \(manIdx + 1)/\(messages.count)").font(.caption.bold()).foregroundStyle(.secondary)
                                if !manCopied.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Label("Đã copy:", systemImage: "doc.on.clipboard.fill")
                                            .font(.caption.bold()).foregroundStyle(.green)
                                        Text(manCopied)
                                            .font(.subheadline).padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(.secondarySystemBackground))
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                                Button { manOpenNow() } label: {
                                    HStack {
                                        Image(systemName: manualPlatform.icon)
                                        Text("Mở \(manualPlatform.label) ngay")
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(manualPlatform.color).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 6).frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                        }
                    }

                    Section {
                        if manRunning {
                            Button(role: .destructive) { stopManual() } label: {
                                Label(store.t("■  Dừng gửi", "■  Stop sending"), systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color.red).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        } else {
                            Button { startManual() } label: {
                                Label(store.t("▶  Bắt đầu gửi thủ công", "▶  Start manual send"), systemImage: "play.circle.fill")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(canStartManual ? store.accentColor : .gray)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(!canStartManual)
                            if messages.isEmpty {
                                Text("Vui lòng nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
                            } else if manualRecipient.isEmpty {
                                Text("Vui lòng nhập người nhận.").font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                }

                // ─────────────────── TAB: Tự động ───────────────────
                if activeTab == 1 {
                    Section("Ứng dụng") {
                        Picker("Nền tảng", selection: $autoPlatformRaw) {
                            ForEach(AutoWebPlatform.allCases, id: \.rawValue) { p in
                                Label(p.label, systemImage: p.icon).tag(p.rawValue)
                            }
                        }
                        if autoPlatform.supportsAutoNav {
                            TextField(autoRecipientHint, text: $autoRecipient)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(autoPlatform == .whatsapp ? .phonePad : .default)
                            recipientPicker($autoRecipient)
                        }
                    }

                    // Tốc độ gửi
                    Section("Tốc độ gửi") {
                        // Preset buttons
                        HStack(spacing: 8) {
                            ForEach(SpeedPreset.allCases, id: \.rawValue) { preset in
                                Button {
                                    speedPresetRaw = preset.rawValue
                                    autoDelay = preset.seconds
                                    // map preset → giây (trong khoảng 0.1–5.0)
                                    switch preset {
                                    case .slow:   autoDelaySec = 5.0
                                    case .normal: autoDelaySec = 2.0
                                    case .fast:   autoDelaySec = 1.0
                                    case .turbo:  autoDelaySec = 0.3
                                    }
                                } label: {
                                    Text(preset.label)
                                        .font(.caption.bold())
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(speedPresetRaw == preset.rawValue
                                                    ? store.accentColor
                                                    : Color(.tertiarySystemBackground))
                                        .foregroundStyle(speedPresetRaw == preset.rawValue ? .white : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        // Tinh chỉnh tốc độ 0.1 – 5.0 giây / tin
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Tốc độ (giây/tin)")
                                Spacer()
                                Text(String(format: "%.1f giây", autoDelaySec))
                                    .foregroundStyle(store.accentColor).font(.subheadline.bold())
                            }
                            Slider(value: $autoDelaySec, in: 0.1...5.0, step: 0.1) { _ in
                                speedPresetRaw = ""
                            }
                            Text("Càng nhỏ gửi càng nhanh (0.1 = rất nhanh, 5.0 = chậm).")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    // Đăng nhập web
                    Section {
                        Button { showWebLogin = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(autoPlatform.color).frame(width: 36, height: 36)
                                    Image(systemName: autoPlatform.icon)
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Mở \(autoPlatform.label) Web")
                                        .font(.subheadline.bold())
                                    Text(autoPlatform.loginHint)
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "qrcode").foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        Text("Session lưu lại — chỉ quét QR 1 lần. Sau khi vào màn hình chat, bấm \"← Quay lại\" rồi Bắt đầu.")
                            .font(.caption2)
                    }

                    // Trạng thái kết nối + danh sách bạn bè
                    Section {
                        HStack {
                            Circle().fill(autoConnected ? .green : .gray).frame(width: 10, height: 10)
                            Text(autoConnected ? "Đã kết nối \(autoPlatform.label)" : "Chưa kết nối")
                                .font(.subheadline.bold())
                                .foregroundStyle(autoConnected ? .green : .secondary)
                            Spacer()
                            Button {
                                Task { await loadFriends() }
                            } label: {
                                HStack(spacing: 4) {
                                    if loadingFriends { ProgressView() }
                                    Text("Tải danh sách").font(.caption)
                                }
                            }
                        }
                        if !autoFriends.isEmpty {
                            Text(store.t("Chọn người để nhắn:", "Choose recipients:")).font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(autoFriends, id: \.self) { name in
                                        Button {
                                            Task { await pickFriend(name) }
                                        } label: {
                                            Label(name, systemImage: "person.crop.circle")
                                                .font(.caption)
                                                .padding(.horizontal, 10).padding(.vertical, 6)
                                                .background(selectedFriend == name
                                                            ? store.accentColor.opacity(0.25)
                                                            : Color(.tertiarySystemBackground))
                                                .clipShape(Capsule()).lineLimit(1)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        } else if autoConnected {
                            Text("Bấm \"Tải danh sách\" để lấy bạn bè/cuộc trò chuyện.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    } header: { Text("Kết nối & người nhận") }

                    // ───── Zalo: nhắn từng thành viên nhóm (best-effort) ─────
                    if autoPlatform == .zalo {
                        Section {
                            Text("1) Mở \"Mở Zalo Web\" → vào đúng NHÓM cần gửi → quay lại đây. 2) Bấm Quét (app tự mở danh sách thành viên đang ẩn rồi gom tên). 3) Bấm gửi cho từng người.")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button {
                                Task { await scanZaloMembers() }
                            } label: {
                                HStack {
                                    if scanningMembers { ProgressView() }
                                    Label("Quét thành viên nhóm", systemImage: "person.3.sequence")
                                }
                            }.disabled(scanningMembers || blasting)

                            if !zaloMembers.isEmpty {
                                Text("Đã quét \(zaloMembers.count) thành viên")
                                    .font(.caption).foregroundStyle(.green)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(zaloMembers, id: \.self) { m in
                                            Text(m).font(.caption2).lineLimit(1)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color(.tertiarySystemBackground)).clipShape(Capsule())
                                        }
                                    }
                                }
                                if blasting {
                                    HStack {
                                        ProgressView()
                                        Text("Đang gửi \(blastDone)/\(zaloMembers.count)…").font(.caption)
                                        Spacer()
                                        Button("Dừng", role: .destructive) { stopBlast() }
                                    }
                                } else {
                                    Button {
                                        startBlast()
                                    } label: {
                                        Label("Gửi tin cho TỪNG thành viên", systemImage: "paperplane.fill")
                                            .frame(maxWidth: .infinity).frame(height: 42)
                                            .background(messages.isEmpty ? Color.gray : store.accentColor)
                                            .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                                    }.buttonStyle(.plain).disabled(messages.isEmpty)
                                    if messages.isEmpty {
                                        Text("Nhập nội dung tin nhắn ở trên trước.").font(.caption2).foregroundStyle(.red)
                                    }
                                }
                            }
                        } header: { Text("Zalo · Nhắn từng thành viên nhóm (thử nghiệm)") }
                    }

                    // Kết quả
                    if !autoStatuses.isEmpty {
                        Section("Kết quả gửi") {
                            ForEach(Array(autoStatuses.enumerated()), id: \.offset) { i, s in
                                HStack(spacing: 8) {
                                    Image(systemName: s.icon).foregroundStyle(s.iconColor)
                                    Text(i < messages.count ? messages[i] : "")
                                        .font(.caption).lineLimit(1).strikethrough(s == .ok)
                                    Spacer()
                                    Text(s.label).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Đếm ngược
                    if autoRunning {
                        Section {
                            HStack {
                                Spacer()
                                VStack(spacing: 6) {
                                    ZStack {
                                        Circle().stroke(Color(.systemFill), lineWidth: 5).frame(width: 64, height: 64)
                                        Circle()
                                            .trim(from: 0, to: autoCountdown > 0 ? CGFloat(autoCountdown) / CGFloat(autoDelay) : 0)
                                            .stroke(store.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                            .frame(width: 64, height: 64)
                                            .rotationEffect(.degrees(-90))
                                            .animation(.linear(duration: 1), value: autoCountdown)
                                        Text("\(autoCountdown)").font(.title3.monospacedDigit().bold())
                                    }
                                    Text("Tin \(min(autoIdx + 1, messages.count))/\(messages.count)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }.listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        if autoRunning {
                            Button(role: .destructive) { stopAuto() } label: {
                                Label(store.t("■  Dừng gửi", "■  Stop sending"), systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color.red).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        } else {
                            Button { startAuto() } label: {
                                Label("▶  Bắt đầu tự động gửi", systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(canStartAuto ? store.accentColor : .gray)
                                    .foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).disabled(!canStartAuto)
                            if messages.isEmpty {
                                Text("Vui lòng nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
                            } else if autoPlatform.supportsAutoNav && autoRecipient.isEmpty {
                                Text("Vui lòng nhập người nhận.").font(.caption2).foregroundStyle(.red)
                            }
                        }
                    }
                }

                // ─────────────────── TAB: Tool nhóm ───────────────────
                if activeTab == 2 { toolGroupSections }
            }
            .navigationTitle(activeTab == 0 ? "Nhắn tin thủ công 📋"
                             : (activeTab == 1 ? "Nhắn tin tự động ⚡" : "Tool nhóm 👥"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onAppear { activeTab = initialTab }
            .onDisappear { stopManual(); stopAuto(); stopBlast(); stopTool() }
            .sheet(isPresented: $showWebLogin, onDismiss: {
                Task {
                    if activeTab == 2 { await loadToolFriends() }
                    else { await checkConnected(); if autoConnected { await loadFriends() } }
                }
            }) {
                let p = activeTab == 2 ? toolPlatform : autoPlatform
                HubBrowserSheet(
                    webView: HubWebViews.shared.view(for: p),
                    initialURL: p.homeURL,
                    platformLabel: p.label
                )
            }
            .onChange(of: autoPlatformRaw) { _ in
                autoConnected = false; autoFriends = []; selectedFriend = ""
                Task { await checkConnected() }
            }
            .onChange(of: toolPlatformRaw) { _ in
                toolConnected = false; toolFriends = []; toolSelected = []
            }
            .onChange(of: toolImageItem) { item in
                guard let item else { return }
                Task { toolImageData = try? await item.loadTransferable(type: Data.self) }
            }
            .task { await checkConnected() }
        }
    }

    // MARK: - Web: kết nối & danh sách bạn bè
    private var toolPlatform: AutoWebPlatform { AutoWebPlatform(rawValue: toolPlatformRaw) ?? .messenger }

    @MainActor private func evalOn(_ p: AutoWebPlatform, _ js: String) async -> String {
        let wv = HubWebViews.shared.view(for: p)
        let r = try? await wv.evaluateJavaScript(js)
        return (r as? String) ?? ""
    }
    @MainActor private func evalAuto(_ js: String) async -> String { await evalOn(autoPlatform, js) }
    private func checkConnected() async {
        guard autoPlatform.supportsAutoNav || autoPlatform == .zalo || autoPlatform == .messenger || autoPlatform == .instagram else {
            autoConnected = false; return
        }
        autoConnected = (await evalAuto(autoPlatform.loginCheckJS)) == "in"
    }
    private func loadFriends() async {
        loadingFriends = true; defer { loadingFriends = false }
        await checkConnected()
        let json = await evalAuto(autoPlatform.chatListJS)
        if let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            autoFriends = arr.filter { !$0.isEmpty }
        }
    }
    private func pickFriend(_ name: String) async {
        selectedFriend = name
        autoRecipient = name
        _ = await evalAuto(autoPlatform.openChatJS(name))   // mở đúng cuộc trò chuyện
    }

    // MARK: - Zalo: quét & nhắn từng thành viên nhóm (best-effort)
    // Quét 1 bước: cuộn danh sách thành viên xuống + trả tên đang hiện (gọi lặp để gom hết)
    private var zaloScanStepJS: String {
        """
        (function(){
          // tìm container có thể cuộn (panel thành viên)
          var nodes=document.querySelectorAll('div,ul,section');
          var sc=null;
          for(var i=0;i<nodes.length;i++){
            var n=nodes[i];
            if(n.scrollHeight>n.clientHeight+30 && n.clientHeight>120 &&
               /member|thành viên|danh sách/i.test((n.className||'')+(n.getAttribute('aria-label')||''))){ sc=n; break; }
          }
          if(!sc){ for(var j=0;j<nodes.length;j++){ if(nodes[j].scrollHeight>nodes[j].clientHeight+200 && nodes[j].clientHeight>200){sc=nodes[j];break;} } }
          if(sc){ sc.scrollTop = sc.scrollTop + Math.max(300, sc.clientHeight-60); }
          var out=[],seen={};
          var sels=['[class*="member-item"]','[class*="group-member"]','[class*="memberItem"]',
                    '[class*="member"] [class*="name"]','[class*="member"] [title]','[role="listitem"] [title]'];
          sels.forEach(function(s){
            document.querySelectorAll(s).forEach(function(e){
              var t=(e.getAttribute('title')||e.textContent||'').trim();
              if(t&&t.length>=1&&t.length<=50&&!seen[t]){seen[t]=1;out.push(t);}
            });
          });
          return JSON.stringify(out);
        })();
        """
    }
    private func zaloMessageMemberJS(_ name: String) -> String {
        let esc = name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return """
        (function(){
          var target='\(esc)';
          var rows=document.querySelectorAll('[class*="member"],[role="listitem"],[class*="item"]');
          for(var i=0;i<rows.length;i++){
            if((rows[i].textContent||'').indexOf(target)>=0){
              rows[i].click();
              setTimeout(function(){
                var bs=document.querySelectorAll('button,[role="button"],div,a,span');
                for(var j=0;j<bs.length;j++){
                  var t=(bs[j].textContent||'').trim().toLowerCase();
                  if(t==='nhắn tin'||t==='gửi tin nhắn'||t==='message'){bs[j].click();return;}
                }
              },700);
              return 'ok';
            }
          }
          return 'not_found';
        })();
        """
    }

    // Tự động MỞ danh sách thành viên nhóm (đang ẩn) trước khi quét
    private func revealZaloMembers() async {
        // B1: mở panel thông tin nhóm (icon/tên nhóm trên thanh tiêu đề)
        _ = await evalAuto("""
        (function(){
          var sel=['[title*="Thông tin"]','[aria-label*="Thông tin"]','[data-translate-title*="info"]',
                   '[class*="header"] [class*="info"]','[class*="chat-header"] [class*="icon"]'];
          for(var i=0;i<sel.length;i++){var e=document.querySelector(sel[i]);if(e){e.click();return 'ok';}}
          // fallback: bấm vào tên nhóm trên header
          var h=document.querySelector('[class*="chat-header"] [class*="name"],[class*="conv-header"] [class*="title"]');
          if(h){h.click();return 'ok';}
          return 'no';
        })();
        """)
        try? await Task.sleep(nanoseconds: 800_000_000)
        // B2: bấm mục "Thành viên" để bung danh sách
        _ = await evalAuto("""
        (function(){
          var els=document.querySelectorAll('div,span,a,button,[role="button"]');
          for(var i=0;i<els.length;i++){
            var t=(els[i].textContent||'').trim().toLowerCase();
            if((t.indexOf('thành viên')>=0||t.indexOf('members')>=0||t.indexOf('xem thành viên')>=0)&&t.length<40){
              els[i].click();return 'ok';
            }
          }
          return 'no';
        })();
        """)
        try? await Task.sleep(nanoseconds: 900_000_000)
    }

    private func scanZaloMembers() async {
        scanningMembers = true; defer { scanningMembers = false }
        await revealZaloMembers()   // tự mở danh sách thành viên (đang ẩn)
        var seen = Set<String>()
        var ordered: [String] = []
        // Cuộn & gom dần tối đa ~15 lần để lấy hết thành viên (danh sách ảo hoá)
        for _ in 0..<15 {
            let json = await evalAuto(zaloScanStepJS)
            if let data = json.data(using: .utf8),
               let arr = try? JSONDecoder().decode([String].self, from: data) {
                for n in arr where !n.isEmpty && !seen.contains(n) {
                    seen.insert(n); ordered.append(n)
                }
            }
            zaloMembers = ordered   // cập nhật dần cho người dùng thấy
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        zaloMembers = ordered
    }

    private func startBlast() {
        guard !messages.isEmpty, !zaloMembers.isEmpty else { return }
        blasting = true; blastIdx = 0; blastDone = 0
        let members = zaloMembers
        let delay = max(0.1, min(autoDelaySec, 5.0))
        blastTask = Task { @MainActor in
            for (i, name) in members.enumerated() {
                guard blasting, !Task.isCancelled else { break }
                blastIdx = i
                _ = await evalAuto(zaloMessageMemberJS(name))     // mở DM với thành viên
                try? await Task.sleep(nanoseconds: 2_500_000_000) // chờ mở khung chat
                for msg in messages {
                    guard blasting, !Task.isCancelled else { break }
                    _ = await evalAuto(AutoWebPlatform.zalo.sendJS(msg))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                blastDone = i + 1
                // quay lại danh sách thành viên cho người kế tiếp (nếu có nút back)
                _ = await evalAuto("(function(){var b=document.querySelector('[class*=\"back\"],[aria-label=\"Quay lại\"],[aria-label=\"Back\"]');if(b){b.click();return 'ok';}return '';})();")
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            blasting = false
        }
    }
    private func stopBlast() {
        blastTask?.cancel(); blastTask = nil; blasting = false
    }

    // MARK: - Tab 3: Tool nhóm (gửi hàng loạt nhiều bạn — Messenger / Zalo)
    @ViewBuilder private var toolGroupSections: some View {
        Section("Nền tảng") {
            Picker("Nền tảng", selection: $toolPlatformRaw) {
                Text("Facebook / Messenger").tag("messenger")
                Text("Zalo").tag("zalo")
            }.pickerStyle(.segmented)
            HStack {
                Circle().fill(toolConnected ? .green : .gray).frame(width: 10, height: 10)
                Text(toolConnected ? "Đã kết nối \(toolPlatform.label)" : "Chưa kết nối")
                    .font(.subheadline.bold()).foregroundStyle(toolConnected ? .green : .secondary)
                Spacer()
                Button("Mở Web đăng nhập") { showWebLogin = true }.font(.caption)
            }
        }

        Section {
            Button {
                Task { await loadToolFriends() }
            } label: {
                HStack { if loadingTool { ProgressView() }
                    Label("Tải danh sách bạn bè", systemImage: "person.2.crop.square.stack") }
            }.disabled(loadingTool || toolRunning)
            if !toolFriends.isEmpty {
                HStack {
                    Text("Đã chọn \(toolSelected.count)/\(toolFriends.count)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(toolSelected.count == toolFriends.count ? "Bỏ chọn tất cả" : "Chọn tất cả") {
                        if toolSelected.count == toolFriends.count { toolSelected.removeAll() }
                        else { toolSelected = Set(toolFriends) }
                    }.font(.caption.bold())
                }
                ForEach(toolFriends, id: \.self) { name in
                    Button {
                        if toolSelected.contains(name) { toolSelected.remove(name) } else { toolSelected.insert(name) }
                    } label: {
                        HStack {
                            Image(systemName: toolSelected.contains(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(toolSelected.contains(name) ? store.accentColor : .secondary)
                            Text(name).foregroundStyle(.primary).lineLimit(1)
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                }
            } else if toolConnected {
                Text("Bấm \"Tải danh sách bạn bè\" để lấy danh sách.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } header: { Text("Danh sách bạn bè") }

        Section("Ảnh đính kèm (tuỳ chọn)") {
            PhotosPicker(selection: $toolImageItem, matching: .images) {
                Label(toolImageData == nil ? "Tải ảnh lên để gửi kèm" : "Đã chọn ảnh — đổi ảnh khác",
                      systemImage: "photo.badge.plus")
            }
            if toolImageData != nil {
                Button("Bỏ ảnh", role: .destructive) { toolImageData = nil; toolImageItem = nil }
                    .font(.caption)
            }
            Text("Nội dung gửi lấy từ ô \"Soạn thảo tin nhắn\" ở trên. Tốc độ dùng chung với tab Tự động.")
                .font(.caption2).foregroundStyle(.secondary)
        }

        Section {
            if toolRunning {
                HStack {
                    ProgressView()
                    Text("Đang gửi \(toolDone)/\(toolSelected.count)…").font(.caption)
                    Spacer()
                    Button("Dừng", role: .destructive) { stopTool() }
                }
            } else {
                Button {
                    startTool()
                } label: {
                    Label("Gửi cho \(toolSelected.count) người đã chọn", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(canStartTool ? store.accentColor : .gray)
                        .foregroundStyle(.white).clipShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).disabled(!canStartTool)
                if toolSelected.isEmpty { Text("Chọn ít nhất 1 người.").font(.caption2).foregroundStyle(.red) }
                else if messages.isEmpty && toolImageData == nil {
                    Text("Nhập nội dung hoặc chọn ảnh để gửi.").font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var canStartTool: Bool { !toolSelected.isEmpty && (!messages.isEmpty || toolImageData != nil) }

    private func loadToolFriends() async {
        loadingTool = true; defer { loadingTool = false }
        toolConnected = (await evalOn(toolPlatform, toolPlatform.loginCheckJS)) == "in"
        let json = await evalOn(toolPlatform, toolPlatform.chatListJS)
        if let data = json.data(using: .utf8),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            toolFriends = arr.filter { !$0.isEmpty }
        }
    }

    // JS đính ảnh từ data URL vào ô soạn tin (best-effort)
    private func attachImageJS(_ dataURL: String) -> String {
        return """
        (function(){
          try{
            var inp=document.querySelector('input[type=file]');
            if(!inp)return 'no_input';
            var arr='\(dataURL)'.split(','),mime=arr[0].match(/:(.*?);/)[1],
                bstr=atob(arr[1]),n=bstr.length,u8=new Uint8Array(n);
            while(n--){u8[n]=bstr.charCodeAt(n);}
            var file=new File([u8],'image.jpg',{type:mime});
            var dt=new DataTransfer();dt.items.add(file);
            inp.files=dt.files;
            inp.dispatchEvent(new Event('change',{bubbles:true}));
            return 'ok';
          }catch(e){return 'err';}
        })();
        """
    }

    private func startTool() {
        guard canStartTool else { return }
        toolRunning = true; toolDone = 0
        let names = toolFriends.filter { toolSelected.contains($0) }
        let p = toolPlatform
        let delay = max(0.1, min(autoDelaySec, 5.0))
        let imgURL: String? = toolImageData.map { "data:image/jpeg;base64,\($0.base64EncodedString())" }
        let msgs = messages
        toolTask = Task { @MainActor in
            for (i, name) in names.enumerated() {
                guard toolRunning, !Task.isCancelled else { break }
                _ = await evalOn(p, p.openChatJS(name))           // mở chat với người này
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                for msg in msgs {
                    guard toolRunning, !Task.isCancelled else { break }
                    _ = await evalOn(p, p.sendJS(msg))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                if let imgURL {
                    _ = await evalOn(p, attachImageJS(imgURL))
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    _ = await evalOn(p, p.sendJS(""))             // bấm gửi ảnh
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                toolDone = i + 1
            }
            toolRunning = false
        }
    }
    private func stopTool() {
        toolTask?.cancel(); toolTask = nil; toolRunning = false
    }

    // MARK: - Computed helpers

    private var canStartManual: Bool { !messages.isEmpty && !manualRecipient.isEmpty }
    private var canStartAuto: Bool {
        !messages.isEmpty && (!autoPlatform.supportsAutoNav || !autoRecipient.isEmpty)
    }
    private var manualRecipientHint: String {
        switch manualPlatformId {
        case "telegram":                       return "@username"
        case "zalo", "imessage", "viber":     return "Số điện thoại (vd 0901234567)"
        case "whatsapp":                       return "SĐT quốc tế (vd +84901234567)"
        default:                               return "Username hoặc SĐT"
        }
    }
    private var autoRecipientHint: String {
        autoPlatform == .whatsapp ? "SĐT quốc tế (vd +84901234567)" : "@username hoặc SĐT"
    }

    // MARK: - Manual session

    private func startManual() {
        guard canStartManual else { return }
        manIdx = 0; manRunning = true
        manCopyAndOpen(messages[0])
        manScheduleNext()
    }

    private func stopManual() {
        manTask?.cancel(); manTask = nil
        manRunning = false; manCountdown = 0; manCopied = ""
    }

    private func manOpenNow() {
        guard manIdx < messages.count else { return }
        manOpenInApp(messages[manIdx])
    }

    private func manCopyAndOpen(_ text: String) {
        UIPasteboard.general.string = text
        manCopied = text
        manOpenInApp(text)
    }

    private func manOpenInApp(_ text: String) {
        let enc = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let urlStr = manualPlatform.urlScheme(manualRecipient.trimmingCharacters(in: .whitespaces), enc)
        if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
    }

    private func manScheduleNext() {
        manTask?.cancel()
        manTask = Task {
            for i in stride(from: manualDelay, through: 0, by: -1) {
                guard !Task.isCancelled else { return }
                await MainActor.run { manCountdown = i }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                manIdx += 1
                if manIdx < messages.count {
                    manCopyAndOpen(messages[manIdx])
                    manScheduleNext()
                } else {
                    stopManual()
                }
            }
        }
    }

    // MARK: - Auto session

    private func startAuto() {
        guard canStartAuto else { return }
        autoStatuses = Array(repeating: .pending, count: messages.count)
        autoIdx = 0; autoRunning = true

        let wv = HubWebViews.shared.view(for: autoPlatform)
        let usePicked = !selectedFriend.isEmpty
        if usePicked {
            // Đã chọn bạn từ danh sách → mở đúng cuộc trò chuyện đó (không điều hướng theo username)
            _ = wv.evaluateJavaScript(autoPlatform.openChatJS(selectedFriend))
        } else if autoPlatform.supportsAutoNav, let url = autoPlatform.chatURL(recipient: autoRecipient) {
            wv.load(URLRequest(url: url))
        }
        autoTask = Task { @MainActor in
            let wait: UInt64 = (usePicked || autoPlatform.supportsAutoNav) ? 4_000_000_000 : 2_000_000_000
            try? await Task.sleep(nanoseconds: wait)
            await autoLoop()
        }
    }

    @MainActor
    private func autoLoop() async {
        while autoIdx < messages.count {
            guard autoRunning, !Task.isCancelled else { return }
            let idx = autoIdx
            autoStatuses[idx] = .sending
            let wv = HubWebViews.shared.view(for: autoPlatform)
            let js = autoPlatform.sendJS(messages[idx])
            do {
                let r = try await wv.evaluateJavaScript(js)
                autoStatuses[idx] = (r as? String) == "ok" ? .ok : .fail
            } catch {
                autoStatuses[idx] = .fail
            }
            autoIdx += 1
            guard autoIdx < messages.count else { break }
            // Chờ theo tốc độ tinh chỉnh 0.1–5.0 giây (chia nhỏ để vẫn dừng được giữa chừng)
            let total = max(0.1, min(autoDelaySec, 5.0))
            autoCountdown = Int(ceil(total))
            var remain = total
            while remain > 0 {
                guard autoRunning, !Task.isCancelled else { return }
                let step = min(0.1, remain)
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                remain -= step
                autoCountdown = Int(ceil(remain))
            }
        }
        autoRunning = false; autoCountdown = 0
    }

    private func stopAuto() {
        autoTask?.cancel(); autoTask = nil
        autoRunning = false; autoCountdown = 0
    }
}

// MARK: - Send state

private enum HubSendState: Equatable {
    case pending, sending, ok, fail
    var icon: String {
        switch self { case .pending: return "clock"; case .sending: return "arrow.up.circle"
        case .ok: return "checkmark.circle.fill"; case .fail: return "xmark.circle.fill" }
    }
    var iconColor: Color {
        switch self { case .pending: return .secondary; case .sending: return .orange
        case .ok: return .green; case .fail: return .red }
    }
    var label: String {
        switch self { case .pending: return "Chờ"; case .sending: return "Đang gửi"
        case .ok: return "Đã gửi ✓"; case .fail: return "Lỗi ✗" }
    }
}

// MARK: - Browser sheet

struct HubBrowserSheet: View {
    let webView: WKWebView
    let initialURL: URL
    let platformLabel: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            HubWebViewRepresentable(webView: webView)
                .ignoresSafeArea()
                .navigationTitle("\(platformLabel) Web")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("← Quay lại app") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { webView.reload() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
        }
        .onAppear { if webView.url == nil { webView.load(URLRequest(url: initialURL)) } }
    }
}

struct HubWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
