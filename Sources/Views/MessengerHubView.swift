import SwiftUI
import WebKit

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

    @State private var autoRunning  = false
    @State private var autoIdx      = 0
    @State private var autoCountdown = 0
    @State private var autoStatuses: [HubSendState] = []
    @State private var autoTask: Task<Void, Never>?
    @State private var showWebLogin = false

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

    var body: some View {
        NavigationStack {
            Form {
                // Header
                Section {
                    KHeroHeader(
                        icon: activeTab == 0 ? "doc.on.clipboard.fill" : "bolt.horizontal.fill",
                        title: activeTab == 0 ? "Nhắn tin thủ công" : "Nhắn tin tự động",
                        subtitle: activeTab == 0
                            ? "Copy clipboard → paste & gửi trong app"
                            : "Quét QR đăng nhập → gửi thẳng qua web")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                // Mode switcher
                Section {
                    Picker("Chế độ", selection: $activeTab) {
                        Label("📋  Thủ công", systemImage: "doc.on.clipboard").tag(0)
                        Label("⚡  Tự động Web", systemImage: "bolt.fill").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: activeTab) { _ in
                        if manRunning { stopManual() }
                        if autoRunning { stopAuto() }
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
                        Label("Soạn thảo tin nhắn", systemImage: "square.and.pencil")
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
                                Label("■  Dừng gửi", systemImage: "stop.circle.fill")
                                    .frame(maxWidth: .infinity).frame(height: 44)
                                    .background(Color.red).foregroundStyle(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        } else {
                            Button { startManual() } label: {
                                Label("▶  Bắt đầu gửi thủ công", systemImage: "play.circle.fill")
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
                                Label("■  Dừng gửi", systemImage: "stop.circle.fill")
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
            }
            .navigationTitle(activeTab == 0 ? "Nhắn tin thủ công 📋" : "Nhắn tin tự động ⚡")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onAppear { activeTab = initialTab }
            .onDisappear { stopManual(); stopAuto() }
            .sheet(isPresented: $showWebLogin) {
                HubBrowserSheet(
                    webView: HubWebViews.shared.view(for: autoPlatform),
                    initialURL: autoPlatform.chatURL(recipient: autoRecipient) ?? autoPlatform.homeURL,
                    platformLabel: autoPlatform.label
                )
            }
        }
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
        if autoPlatform.supportsAutoNav, let url = autoPlatform.chatURL(recipient: autoRecipient) {
            wv.load(URLRequest(url: url))
        }
        autoTask = Task { @MainActor in
            let wait: UInt64 = autoPlatform.supportsAutoNav ? 5_000_000_000 : 2_000_000_000
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
