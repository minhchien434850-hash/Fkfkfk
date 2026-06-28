import SwiftUI
import WebKit

// ============================ Web Messenger: dùng tài khoản thật, quét QR đăng nhập ============================
// WKWebView load web version của từng app, user quét QR 1 lần — session lưu lại mãi
// Sau khi login, app inject JS tự động gửi từng tin nhắn

private enum WebMsgPlatform: String, CaseIterable {
    case telegram  = "telegram"
    case whatsapp  = "whatsapp"
    case zalo      = "zalo"
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

    // URL tự điều hướng đến chat của người nhận (Telegram & WhatsApp hỗ trợ)
    func chatURL(recipient: String) -> URL? {
        let r = recipient.trimmingCharacters(in: .whitespaces)
        guard !r.isEmpty else { return nil }
        switch self {
        case .telegram:
            let user = r.hasPrefix("@") ? String(r.dropFirst()) : r
            return URL(string: "https://web.telegram.org/k/#@\(user)")
        case .whatsapp:
            let phone = r.filter { $0.isNumber || $0 == "+" }
            return URL(string: "https://web.whatsapp.com/send?phone=\(phone)")
        default:
            return nil  // Zalo / Messenger / Instagram: điều hướng thủ công trong trình duyệt
        }
    }

    // JavaScript inject vào web page để gõ + gửi tin
    func sendJS(message: String) -> String {
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
                var btn=document.querySelector('.btn-send,.btn-icon.btn-send-message');
                if(btn){btn.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },400);
              return 'ok';
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
                var btn=document.querySelector('[data-testid="send"]')
                       ||document.querySelector('button[aria-label="Send"]')
                       ||document.querySelector('span[data-icon="send"]');
                if(btn){btn.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },500);
              return 'ok';
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
                var btn=document.querySelector('button[type="submit"]')
                       ||document.querySelector('.send-btn')
                       ||document.querySelector('[aria-label="Gửi"],[aria-label="Send"]');
                if(btn){btn.click();return;}
                el.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',keyCode:13,bubbles:true}));
              },400);
              return 'ok';
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
              },400);
              return 'ok';
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
                var btns=document.querySelectorAll('button,[role="button"]');
                for(var b of btns){
                  var lbl=(b.getAttribute('aria-label')||'').toLowerCase();
                  var txt=(b.textContent||'').trim().toLowerCase();
                  if(lbl.includes('send')||txt==='send'||txt==='gửi'){b.click();return;}
                }
              },500);
              return 'ok';
            })();
            """
        }
    }

    var loginHint: String {
        switch self {
        case .telegram:  return "Quét mã QR bằng Telegram trên điện thoại"
        case .whatsapp:  return "Quét mã QR bằng WhatsApp → Thiết bị đã liên kết"
        case .zalo:      return "Quét mã QR bằng Zalo trên điện thoại"
        case .messenger: return "Đăng nhập bằng tài khoản Facebook"
        case .instagram: return "Đăng nhập tài khoản Instagram, rồi điều hướng đến đúng conversation"
        }
    }

    // Có hỗ trợ tự điều hướng đến chat không
    var supportsAutoNav: Bool { self == .telegram || self == .whatsapp }
}

// Giữ WKWebView sống để session (cookie) không mất
private final class PersistentWebViews {
    static let shared = PersistentWebViews()
    private var cache: [String: WKWebView] = [:]

    func view(for platform: WebMsgPlatform) -> WKWebView {
        if let v = cache[platform.rawValue] { return v }
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = WKWebsiteDataStore.default()   // cookie lưu xuống disk
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        // Desktop User-Agent để web app hiện đầy đủ (QR code, giao diện chat, ...)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        cache[platform.rawValue] = wv
        return wv
    }
}

// MARK: - View chính

struct WebAutoMessengerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @AppStorage("wamPlatform")  private var platformRaw = "telegram"
    @AppStorage("wamRecipient") private var recipient   = ""
    @AppStorage("wamRawText")   private var rawText     = ""
    @AppStorage("wamDelaySec")  private var delaySec    = 15

    @State private var isRunning  = false
    @State private var currentIdx = 0
    @State private var countdown  = 0
    @State private var statuses: [WMSendState] = []
    @State private var runTask: Task<Void, Never>?
    @State private var showBrowser = false

    private var platform: WebMsgPlatform { WebMsgPlatform(rawValue: platformRaw) ?? .telegram }

    private var messages: [String] {
        rawText.components(separatedBy: ":")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    KHeroHeader(icon: "safari.fill",
                                title: "Web Messenger",
                                subtitle: "Quét QR đăng nhập — gửi tự động, không cần bot")
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                }

                Section("Ứng dụng") {
                    Picker("Nền tảng", selection: $platformRaw) {
                        ForEach(WebMsgPlatform.allCases, id: \.rawValue) { p in
                            Label(p.label, systemImage: p.icon).tag(p.rawValue)
                        }
                    }
                    .onChange(of: platformRaw) { _ in
                        // Reset khi đổi platform
                        if isRunning { stopSession() }
                    }
                }

                // Người nhận (chỉ cần khi platform hỗ trợ auto-nav)
                if platform.supportsAutoNav {
                    Section("Người nhận") {
                        TextField(recipientHint, text: $recipient)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(platform == .whatsapp ? .phonePad : .default)
                    }
                }

                // Giãn cách
                Section {
                    Stepper(value: $delaySec, in: 5...300) {
                        HStack {
                            Text("Giãn cách mỗi tin")
                            Spacer()
                            Text("\(delaySec) giây")
                                .foregroundStyle(store.accentColor)
                                .font(.subheadline.bold())
                        }
                    }
                }

                // Tin nhắn
                Section {
                    TextEditor(text: $rawText)
                        .frame(minHeight: 100)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    HStack {
                        Text("Danh sách tin (dùng : để phân cách)")
                        Spacer()
                        Text("\(messages.count) tin")
                            .font(.caption.bold())
                            .foregroundStyle(store.accentColor)
                    }
                } footer: {
                    Text("Ví dụ: Ê bạn:Trả lời đi:Sao im lặng 😄")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                // Nút mở trình duyệt đăng nhập
                Section {
                    Button { showBrowser = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(platform.color)
                                    .frame(width: 36, height: 36)
                                Image(systemName: platform.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mở \(platform.label) Web")
                                    .font(.subheadline.bold())
                                Text(platform.loginHint)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "qrcode").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Session lưu lại — chỉ cần đăng nhập 1 lần. Sau khi vào được màn hình chat, bấm \"← Quay lại\" rồi nhấn Bắt đầu.")
                        .font(.caption2)
                }

                // Kết quả
                if !statuses.isEmpty {
                    Section("Kết quả gửi") {
                        ForEach(Array(statuses.enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 8) {
                                Image(systemName: s.icon).foregroundStyle(s.color)
                                Text(i < messages.count ? messages[i] : "")
                                    .font(.caption).lineLimit(1)
                                    .strikethrough(s == .ok)
                                Spacer()
                                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Đếm ngược
                if isRunning {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle().stroke(Color(.systemFill), lineWidth: 5)
                                        .frame(width: 64, height: 64)
                                    Circle()
                                        .trim(from: 0, to: countdown > 0 ? CGFloat(countdown) / CGFloat(delaySec) : 0)
                                        .stroke(store.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                        .frame(width: 64, height: 64)
                                        .rotationEffect(.degrees(-90))
                                        .animation(.linear(duration: 1), value: countdown)
                                    Text("\(countdown)").font(.title3.monospacedDigit().bold())
                                }
                                Text("Tin \(min(currentIdx + 1, messages.count))/\(messages.count)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                // Bắt đầu / Dừng
                Section {
                    if isRunning {
                        Button(role: .destructive) { stopSession() } label: {
                            Label("■  Dừng gửi", systemImage: "stop.circle.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.red).foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    } else {
                        Button { startSession() } label: {
                            Label("▶  Bắt đầu tự động gửi", systemImage: "bolt.fill")
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(canStart ? store.accentColor : .gray)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canStart)
                        if messages.isEmpty {
                            Text("Nhập ít nhất 1 tin nhắn.").font(.caption2).foregroundStyle(.red)
                        } else if platform.supportsAutoNav && recipient.isEmpty {
                            Text("Nhập người nhận.").font(.caption2).foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Web Messenger 🌐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
            .onDisappear { stopSession() }
            .sheet(isPresented: $showBrowser) {
                WMBrowserSheet(
                    webView: PersistentWebViews.shared.view(for: platform),
                    initialURL: platform.chatURL(recipient: recipient) ?? platform.homeURL,
                    platformLabel: platform.label
                )
            }
        }
    }

    private var canStart: Bool {
        !messages.isEmpty && (!platform.supportsAutoNav || !recipient.isEmpty)
    }

    private var recipientHint: String {
        switch platform {
        case .telegram:  return "@username hoặc số điện thoại"
        case .whatsapp:  return "SĐT quốc tế (vd +84901234567)"
        default:         return ""
        }
    }

    // MARK: - Session

    private func startSession() {
        guard canStart else { return }
        statuses = Array(repeating: .pending, count: messages.count)
        currentIdx = 0
        isRunning = true

        let wv = PersistentWebViews.shared.view(for: platform)
        if platform.supportsAutoNav, let url = platform.chatURL(recipient: recipient) {
            wv.load(URLRequest(url: url))
        }

        runTask = Task { @MainActor in
            // Chờ trang navigate xong (5s với auto-nav, 2s với manual)
            let waitNs: UInt64 = platform.supportsAutoNav ? 5_000_000_000 : 2_000_000_000
            try? await Task.sleep(nanoseconds: waitNs)
            await runLoop()
        }
    }

    @MainActor
    private func runLoop() async {
        while currentIdx < messages.count {
            guard isRunning, !Task.isCancelled else { return }
            let idx = currentIdx
            statuses[idx] = .sending

            let wv = PersistentWebViews.shared.view(for: platform)
            let js = platform.sendJS(message: messages[idx])
            do {
                let result = try await wv.evaluateJavaScript(js)
                statuses[idx] = (result as? String) == "ok" ? .ok : .fail
            } catch {
                statuses[idx] = .fail
            }

            currentIdx += 1
            guard currentIdx < messages.count else { break }

            // Đếm ngược đến tin tiếp
            for i in stride(from: delaySec, through: 0, by: -1) {
                guard isRunning, !Task.isCancelled else { return }
                countdown = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        isRunning = false
        countdown = 0
    }

    private func stopSession() {
        runTask?.cancel(); runTask = nil
        isRunning = false; countdown = 0
    }
}

private enum WMSendState: Equatable {
    case pending, sending, ok, fail
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .sending: return "arrow.up.circle"
        case .ok:      return "checkmark.circle.fill"
        case .fail:    return "xmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .pending: return .secondary
        case .sending: return .orange
        case .ok:      return .green
        case .fail:    return .red
        }
    }
    var label: String {
        switch self {
        case .pending: return "Chờ"
        case .sending: return "Đang gửi"
        case .ok:      return "Đã gửi ✓"
        case .fail:    return "Lỗi ✗"
        }
    }
}

// MARK: - Trình duyệt QR / đăng nhập

struct WMBrowserSheet: View {
    let webView: WKWebView
    let initialURL: URL
    let platformLabel: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            WMWebViewRepresentable(webView: webView)
                .ignoresSafeArea()
                .navigationTitle("\(platformLabel) Web")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("← Quay lại app") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            webView.reload()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
        }
        .onAppear {
            if webView.url == nil {
                webView.load(URLRequest(url: initialURL))
            }
        }
    }
}

struct WMWebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
