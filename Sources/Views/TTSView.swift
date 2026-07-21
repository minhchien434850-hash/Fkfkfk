import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers

// Mô hình (LiveEventType, VoiceStyle, ElevenTonePreset…) đã tách sang TTSModels.swift.

// ======================== Giao diện ========================
struct TTSView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var tts = TTSEngine()

    @State private var freeText = ""
    @State private var personName = ""
    @State private var content = ""
    @State private var selectedEvent = "gift"
    @State private var search = ""
    private let previewSynth = AVSpeechSynthesizer()

    // ----- Tải file âm thanh → lấy link cho âm thông báo -----
    @State private var showAudioImporter = false
    @State private var audioImportType = "gift"   // "__lib" = thêm vào kho; còn lại = gán cho sự kiện
    @State private var audioUploading = false
    @State private var audioError: String?        // báo lỗi tải file âm thanh (thay vì im lặng)
    @State private var newCustomLink = ""         // ô dán link liên tiếp để thêm vào kho
    @State private var audioDone = 0              // số file đã tải xong (tải nhiều file cùng lúc)
    @State private var audioTotal = 0             // tổng số file đang tải
    // ----- Đồng bộ bộ âm lên server (CHỈ ADMIN) -----
    @State private var syncing = false
    @State private var syncMsg: String?

    // ----- Câu cà khịa tự thêm -----
    @State private var newRoast = ""

    // ----- Dịch tự động sang tiếng Việt + lọc giọng (LƯU LẠI — giữ nguyên khi mở lại app) -----
    @AppStorage("tts_translate_to_vi") private var translateToVi = true
    @AppStorage("tts_only_vi_voices") private var onlyVietnameseVoices = false

    // ----- TikTok Live: tự động đọc bình luận (như TikFinity) -----
    @AppStorage("tts_tiktok_id") private var tiktokId = ""
    @State private var liveConnected = false
    @State private var liveStatus = ""
    @State private var liveError: String?
    @State private var lastEventId = 0
    @State private var pollTask: Task<Void, Never>?
    @State private var readTypes: Set<String> = TTSView.loadReadTypes()

    // Loại sự kiện đọc — nhớ lại lựa chọn (lưu chuỗi phân tách bằng dấu phẩy).
    private static func loadReadTypes() -> Set<String> {
        if let s = UserDefaults.standard.string(forKey: "tts_read_types") {
            return Set(s.split(separator: ",").map(String.init))
        }
        return ["comment", "gift", "follow", "share", "join"]
    }
    @State private var liveFeed: [TikTokLiveEvent] = []
    @State private var liveCounts: [String: Int] = [:]   // chẩn đoán: máy chủ NHẬN được loại nào
    // ----- Trình đọc trên trình duyệt (TikTok Studio / OBS) -----
    @State private var readerURL = ""
    @State private var readerBusy = false
    @State private var readerMsg: String?

    // ----- Cấu hình câu phát (greetings) — @AppStorage: tự lưu & tự cập nhật khi đồng bộ -----
    @AppStorage("tts_event_template_join") private var templateJoin = "Chào mừng {name} đã vào phòng"
    @AppStorage("tts_event_template_gift") private var templateGift = "Cảm ơn {name} đã tặng {content}"
    @AppStorage("tts_event_template_comment") private var templateComment = "{name} bình luận: {content}"
    @AppStorage("tts_event_template_follow") private var templateFollow = "Cảm ơn {name} đã theo dõi"
    @AppStorage("tts_event_template_share") private var templateShare = "Cảm ơn {name} đã chia sẻ live"

    // Cờ đã kéo cấu hình TTS từ máy chủ về (chỉ kéo 1 lần mỗi phiên).
    @State private var ttsSyncedFromServer = false

    // Cache danh sách giọng 1 lần khi mở app (speechVoices() rất nặng — tránh gọi mỗi lần render gây lag/đứng)
    private static let cachedVoices: [AVSpeechSynthesisVoice] =
        AVSpeechSynthesisVoice.speechVoices().sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    private static let cachedVietnameseCount: Int =
        cachedVoices.filter { $0.language.hasPrefix("vi") }.count

    private var voices: [AVSpeechSynthesisVoice] {
        var all = Self.cachedVoices
        if onlyVietnameseVoices {
            all = all.filter { $0.language.hasPrefix("vi") }
        }
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.language.localizedCaseInsensitiveContains(search)
        }
    }

    private var vietnameseVoiceCount: Int { Self.cachedVietnameseCount }

    // Danh sách giọng cho chế độ Siri: giọng tiếng Việt trước (chất lượng cao xếp đầu),
    // rồi tới các giọng còn lại. Giúp người dùng chọn nhanh giọng "gần Siri" nhất.
    private var siriCandidateVoices: [AVSpeechSynthesisVoice] {
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q { case .premium: return 0; case .enhanced: return 1; default: return 2 }
        }
        let vi = Self.cachedVoices.filter { $0.language.hasPrefix("vi") }
            .sorted { rank($0.quality) < rank($1.quality) }
        let others = Self.cachedVoices.filter { !$0.language.hasPrefix("vi") }
        return vi + others
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    KHeroHeader(icon: "speaker.wave.2.fill",
                                title: store.t("Đọc văn bản", "Read text"),
                                subtitle: store.t("TTS · đọc bình luận TikTok Live · chạy nền",
                                                  "TTS · read TikTok Live comments · background"))

                    // ----- TikTok Live: tự động đọc bình luận -----
                    section("TikTok Live — tự động đọc bình luận") {
                        HStack {
                            Image(systemName: "music.note.tv.fill").foregroundStyle(.pink)
                            textField("ID / @username TikTok hoặc link LIVE", $tiktokId)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // Chọn loại sự kiện sẽ đọc
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(kLiveEvents) { e in
                                    let on = readTypes.contains(e.id)
                                    Button {
                                        if on { readTypes.remove(e.id) } else { readTypes.insert(e.id) }
                                    } label: {
                                        Label(e.label, systemImage: on ? "checkmark.circle.fill" : e.icon)
                                            .font(.caption)
                                            .padding(.horizontal, 10).padding(.vertical, 7)
                                            .background(on ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        HStack {
                            if liveConnected {
                                Button(role: .destructive) { disconnectLive() } label: {
                                    Label(store.t("Ngắt kết nối", "Disconnect"), systemImage: "stop.circle.fill").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)
                            } else {
                                Button { connectLive() } label: {
                                    Label(store.t("Kết nối & đọc", "Connect & read"), systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(tiktokId.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }

                        HStack(spacing: 6) {
                            Circle().fill(liveStatusColor).frame(width: 8, height: 8)
                            Text(liveStatusText).font(.caption).foregroundStyle(.secondary)
                        }

                        // ----- HƯỚNG DẪN kết nối với TikTok Studio / phòng LIVE -----
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                guideRow("1", "Bật LIVE trên TikTok", "Mở TikTok Studio (hoặc app TikTok) → bấm “Đi LIVE / Go LIVE” để bắt đầu buổi phát trực tiếp.")
                                guideRow("2", "Lấy @username của bạn", "Vào trang hồ sơ TikTok, tên có dạng “@tencuaban”. Chép đúng phần “@tencuaban”.")
                                guideRow("3", "Dán vào ô trên & Kết nối", "Dán @username (hoặc link phòng live) vào ô “ID / @username TikTok…”, chọn loại sự kiện muốn đọc, rồi bấm “Kết nối & đọc”.")
                                guideRow("4", "Nghe đọc realtime", "App đọc bình luận + tặng quà/follow/chia sẻ ngay khi khán giả gửi. Ưu tiên đọc quà/follow/share trước.")
                                Text("Lưu ý: phải ĐANG LIVE thì mới kết nối được. Nếu báo “không tìm thấy phòng live”, kiểm tra @username đúng chưa và bạn đã bấm Go LIVE chưa. Để app đọc khi tắt màn hình, cứ để app chạy nền — âm vẫn phát.")
                                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                                Link("Mở TikTok Studio →", destination: URL(string: "https://www.tiktok.com/studio")!)
                                    .font(.caption)
                            }.padding(.top, 4)
                        } label: {
                            Label(store.t("Hướng dẫn kết nối TikTok Studio / LIVE", "How to connect TikTok Studio / LIVE"),
                                  systemImage: "questionmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                        if let liveError {
                            Text(liveError).font(.caption2).foregroundStyle(.red)
                        }

                        liveDiagnosticLine   // Máy chủ NHẬN được: bình luận / vào / quà…

                        // ƯU TIÊN HIỆN BÌNH LUẬN: bảng bình luận RIÊNG, luôn thấy, không bị
                        // "người vào" lấn át. Giữ tới 40 bình luận gần nhất (mới nhất trên cùng).
                        let comments = liveFeed.filter { $0.type == "comment" }
                        if !comments.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Bình luận", systemImage: "text.bubble.fill")
                                    .font(.caption.bold()).foregroundStyle(Theme.accent)
                                ForEach(comments.suffix(40).reversed()) { ev in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "text.bubble")
                                            .font(.caption2).foregroundStyle(Theme.accent)
                                        Text(renderLive(ev)).font(.caption2)
                                        Spacer()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Các sự kiện khác (vào phòng / quà / follow) — gọn, để RIÊNG bên dưới.
                        let others = liveFeed.filter { $0.type != "comment" }
                        if !others.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(others.suffix(6).reversed()) { ev in
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: kLiveEvents.first { $0.id == ev.type }?.icon ?? "person.fill")
                                            .font(.caption2).foregroundStyle(.secondary)
                                        Text(renderLive(ev)).font(.caption2).foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(.secondarySystemBackground).opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Text("Nhập ID người đang LIVE → app tự đọc bình luận/quà bằng giọng đã chọn. Tiếp tục đọc khi khoá màn hình.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    // ===== Đọc trên TikTok Studio / OBS (qua trình duyệt · TÁCH RIÊNG) =====
                    section("Đọc trên TikTok Studio / OBS (trình duyệt)") {
                        Text("Khác với phần trên: tạo 1 ĐƯỜNG DẪN của máy chủ, mở trên MÁY TÍNH phát live (hoặc thêm làm Browser Source trong OBS / TikTok LIVE Studio). Trang tự đọc bình luận THẲNG trên luồng — không cần mở app. Giọng ĐỒNG BỘ với thiết lập ở đây.")
                            .font(.caption2).foregroundStyle(.secondary)

                        Button { Task { await makeReaderLink() } } label: {
                            HStack {
                                if readerBusy { ProgressView().padding(.trailing, 4) }
                                Label(readerURL.isEmpty ? "Tạo & đồng bộ đường dẫn" : "Cập nhật đồng bộ lại",
                                      systemImage: "link.badge.plus").frame(maxWidth: .infinity)
                            }
                        }.buttonStyle(.borderedProminent)
                            .disabled(readerBusy || tiktokId.trimmingCharacters(in: .whitespaces).isEmpty)

                        if tiktokId.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("Nhập @username TikTok ở ô phía trên trước khi tạo đường dẫn.")
                                .font(.caption2).foregroundStyle(.orange)
                        }

                        if !readerURL.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(readerURL).font(.caption.monospaced())
                                    .textSelection(.enabled).lineLimit(2)
                                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                HStack {
                                    Button { UIPasteboard.general.string = readerURL; readerMsg = "Đã sao chép đường dẫn." } label: {
                                        Label("Sao chép", systemImage: "doc.on.doc.fill").font(.caption)
                                    }.buttonStyle(.bordered)
                                    Button { if let u = URL(string: readerURL) { UIApplication.shared.open(u) } } label: {
                                        Label("Mở thử", systemImage: "safari.fill").font(.caption)
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                        if let readerMsg {
                            Text(readerMsg).font(.caption2).foregroundStyle(.green)
                        }

                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                guideRow("1", "Đặt giọng ở app", "Chọn giọng (ElevenLabs/Google), Voice ID, tốc độ, loại sự kiện muốn đọc — rồi bấm “Tạo & đồng bộ đường dẫn”.")
                                guideRow("2", "Sao chép đường dẫn", "Bấm “Sao chép”. Gửi/mở đường dẫn này trên MÁY TÍNH đang phát live.")
                                guideRow("3", "Thêm vào OBS / TikTok Studio", "OBS: + → Browser → dán đường dẫn (bật “Control audio via OBS”). Hoặc chỉ cần mở đường dẫn bằng Chrome trên máy phát live.")
                                guideRow("4", "Bấm “Bắt đầu đọc”", "Trên trang vừa mở, bấm “Bắt đầu đọc”. Nó tự kết nối phòng LIVE của bạn và đọc bình luận bằng đúng giọng đã đồng bộ.")
                                Text("Lưu ý: đổi giọng/tốc độ trong app thì bấm “Cập nhật đồng bộ lại” rồi tải lại trang. Giọng ElevenLabs dùng key admin trên máy chủ (khách không cần key).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.padding(.top, 4)
                        } label: {
                            Label("Hướng dẫn thêm vào OBS / TikTok Studio", systemImage: "questionmark.circle.fill")
                                .font(.caption.bold()).foregroundStyle(Theme.accent)
                        }
                    }

                    // ----- Cấu hình câu phát (greetings) -----
                    section("Cấu hình câu phát (Greetings & Alerts)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Hỗ trợ {name} để chèn tên người và {content} để chèn tên quà/bình luận.")
                                .font(.caption2).foregroundStyle(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lời chào người vào phòng (Welcome):").font(.caption).bold()
                                textField("Chào mừng {name} đã vào phòng", $templateJoin)
                                    .onChange(of: templateJoin) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_join")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn tặng quà (Gift):").font(.caption).bold()
                                textField("Cảm ơn {name} đã tặng {content}", $templateGift)
                                    .onChange(of: templateGift) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_gift")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Đọc bình luận (Comment):").font(.caption).bold()
                                textField("{name} bình luận: {content}", $templateComment)
                                    .onChange(of: templateComment) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_comment")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn theo dõi (Follow):").font(.caption).bold()
                                textField("Cảm ơn {name} đã theo dõi", $templateFollow)
                                    .onChange(of: templateFollow) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_follow")
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Cảm ơn chia sẻ (Share):").font(.caption).bold()
                                textField("Cảm ơn {name} đã chia sẻ live", $templateShare)
                                    .onChange(of: templateShare) { newValue in
                                        UserDefaults.standard.set(newValue, forKey: "tts_event_template_share")
                                    }
                            }
                        }
                    }

                    // ----- Tự động đọc thông báo định kỳ (quảng cáo / nhắc inbox) -----
                    autoAnnounceSection

                    // ----- Tự động cà khịa lại bình luận khiêu khích -----
                    autoRoastSection

                    // ----- Thông báo livestream -----
                    section("Thông báo livestream") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(kLiveEvents) { e in
                                    Button { selectedEvent = e.id } label: {
                                        Label(e.label, systemImage: e.icon).font(.caption)
                                            .padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(selectedEvent == e.id ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                            .clipShape(Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        textField("Tên người (name)", $personName)
                        if selectedEvent == "gift" || selectedEvent == "comment" {
                            textField(selectedEvent == "gift" ? "Quà (content)" : "Nội dung bình luận", $content)
                        }
                        Button {
                            speakTranslated(renderEvent(), eventType: selectedEvent)
                        } label: {
                            Label(store.t("Đọc thông báo", "Read notice"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(personName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Text(store.t("Xem trước:", "Preview:") + " \(renderEvent())").font(.caption2).foregroundStyle(.secondary)
                    }

                    // ----- Âm thanh thông báo (quà · follow · share) -----
                    notifSoundSection

                    // ----- Đọc văn bản tự do -----
                    section(store.t("Đọc văn bản (tự dịch sang tiếng Việt)", "Read text (auto-translate to Vietnamese)")) {
                        TextEditor(text: $freeText)
                            .font(.body).frame(minHeight: 110)
                            .padding(6).background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Button { speakTranslated(freeText) } label: {
                            Label(store.t("Đọc", "Read"), systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    // ----- Điều khiển phát -----
                    HStack {
                        Button { tts.pauseOrContinue() } label: {
                            Label(tts.isPaused ? store.t("Tiếp tục", "Resume") : store.t("Tạm dừng", "Pause"),
                                  systemImage: tts.isPaused ? "play.fill" : "pause.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking && !tts.isPaused)
                        Button { tts.skipCurrent() } label: {
                            Label(store.t("Bỏ qua", "Skip"), systemImage: "forward.end.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking)
                        Spacer()
                        Button(role: .destructive) { tts.stop() } label: {
                            Label(store.t("Dừng", "Stop"), systemImage: "stop.fill")
                        }.buttonStyle(.bordered).disabled(!tts.isSpeaking && !tts.isPaused)
                    }
                    if tts.pendingCount > 0 {
                        Text(store.t("Đang chờ đọc:", "Queued:") + " \(tts.pendingCount) " + store.t("đoạn", "items"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }

                    // ----- Động cơ & Tinh chỉnh giọng -----
                    section(store.t("Thiết lập Động cơ giọng nói", "Voice engine settings")) {
                        Text(store.t("Động cơ", "Engine")).font(.caption).foregroundStyle(.secondary)
                        // Giọng ElevenLabs chỉ dành cho gói PRO — Free không thấy lựa chọn này
                        // Dùng menu (thả xuống) vì có nhiều động cơ, nhãn dài — segmented sẽ bị chật, khó đọc.
                        Picker(store.t("Động cơ", "Engine"), selection: $tts.engineType) {
                            ForEach(TTSEngine.EngineType.allCases.filter { store.isPro || $0 != .elevenlabs }) { type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                        .onAppear {
                            // Free lỡ đang ở ElevenLabs (từ bản cũ) → đưa về giọng hệ thống
                            if !store.isPro && tts.engineType == .elevenlabs { tts.engineType = .system }
                        }
                        if !store.isPro {
                            Label(store.t("Giọng ElevenLabs (AI) chỉ có ở gói PRO. Nâng cấp để mở khoá.",
                                          "ElevenLabs (AI) voice is PRO-only. Upgrade to unlock."),
                                  systemImage: "crown.fill")
                                .font(.caption2).foregroundStyle(Theme.gold)
                        }

                        Toggle(isOn: $translateToVi) {
                            Label(store.t("Tự dịch sang tiếng Việt khi đọc", "Auto-translate to Vietnamese when reading"), systemImage: "character.bubble")
                                .font(.subheadline)
                        }.tint(Theme.accent)

                        // Bộ chuẩn hoá tiếng Việt (mở rộng tiếng lóng/viết tắt + đọc rõ chữ cái)
                        // ĐÃ TỰ ĐỘNG áp dụng cho ElevenLabs & Chị Google — không cần bật gì thêm.
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                            Text("Đã tự đổi tiếng lóng/viết tắt (ko→không, đc→được, qr→quy rờ…) và đọc rõ chữ cái tiếng Việt cho ElevenLabs & Google.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }

                        // TỐC ĐỘ theo GIỌNG ĐANG CHỌN. ElevenLabs → thanh riêng 0.5–2.0 (ngay ở đây,
                        // không cần vào Cấu hình API). iOS/Siri/Google → tốc độ + cao độ + kiểu giọng.
                        if tts.engineType == .elevenlabs {
                            sliderD("Tốc độ đọc (ElevenLabs)", value: $tts.elevenSpeed, range: 0.5...2.0)
                            slider("Âm lượng", value: $tts.volume, range: 0...1)
                            Text("Kéo trái = chậm rõ · phải = nhanh (0.5× → 2.0×, 1.0× là bình thường). Áp dụng cho giọng ElevenLabs đang chọn.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("Kiểu giọng (iOS · Siri · Google)").font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(kVoiceStyles) { s in
                                        let on = (tts.pitch == s.pitch && tts.rate == s.rate)
                                        Button { tts.pitch = s.pitch; tts.rate = s.rate } label: {
                                            Label(s.label, systemImage: s.icon).font(.caption)
                                                .padding(.horizontal, 12).padding(.vertical, 8)
                                                .background(on ? Theme.accent.opacity(0.25) : Color(.secondarySystemBackground))
                                                .clipShape(Capsule())
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            slider("Tốc độ", value: $tts.rate,
                                   range: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate)
                            slider("Cao độ", value: $tts.pitch, range: 0.5...2.0)
                            slider("Âm lượng", value: $tts.volume, range: 0...1)
                        }

                        // ElevenLabs — đọc tiếng Việt (chỉ PRO)
                        if tts.engineType == .elevenlabs && store.isPro {
                            Divider().padding(.vertical, 4)

                            // --- Chọn tông giọng ElevenLabs ---
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Tông giọng ElevenLabs")
                                    .font(.caption).foregroundStyle(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(kElevenTonePresets) { tone in
                                            let on = tts.elevenToneId == tone.id
                                            Button { tts.elevenToneId = tone.id } label: {
                                                Label(tone.label, systemImage: tone.icon)
                                                    .font(.caption.bold())
                                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                                    .background(on
                                                        ? Color.green.opacity(0.30)
                                                        : Color(.secondarySystemBackground))
                                                    .foregroundStyle(on ? .green : .primary)
                                                    .clipShape(Capsule())
                                                    .overlay(
                                                        Capsule().stroke(on ? Color.green : Color.clear, lineWidth: 1.5)
                                                    )
                                            }.buttonStyle(.plain)
                                        }
                                    }.padding(.vertical, 2)
                                }
                                Text("Chỉ áp dụng khi dùng ElevenLabs API key. Mỗi tông thay đổi cách đọc tiếng Việt (trầm, cảm xúc, rõ ràng…).")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }

                            Divider().padding(.vertical, 4)

                            // ---- Nhập Voice ID ----
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Voice ID")
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                TextField("Dán Voice ID từ ElevenLabs vào đây", text: $tts.elevenVoiceId)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onSubmit { tts.fetchElevenVoiceName(tts.elevenVoiceId) }
                                if !tts.elevenVoiceName.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "person.wave.2.fill")
                                            .foregroundStyle(.green)
                                            .font(.caption)
                                        Text("Giọng: \(tts.elevenVoiceName)")
                                            .font(.caption.bold())
                                            .foregroundStyle(.green)
                                    }
                                } else if !tts.elevenVoiceId.trimmingCharacters(in: .whitespaces).isEmpty {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7)
                                        Text("Đang lấy tên giọng…")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Vào elevenlabs.io → Voices → chép Voice ID dán vào đây. Tên giọng sẽ tự hiện sau khi nhập.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }

                            // CẤU HÌNH API KEY — CHỈ ADMIN vào được. Khách chỉ nhập Voice ID + chỉnh
                            // tốc độ ở trên; giọng ElevenLabs dùng key admin trên máy chủ.
                            if store.isAdmin {
                                Divider().padding(.vertical, 4)
                                NavigationLink {
                                    ElevenLabsKeyView(elevenKey: $tts.elevenKey, elevenVoiceId: $tts.elevenVoiceId, elevenVoiceName: $tts.elevenVoiceName)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "key.fill").foregroundStyle(.green).frame(width: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Cấu hình API key ElevenLabs (Admin)")
                                                .font(.subheadline.bold())
                                            Text("Thiết lập & đồng bộ key dùng chung lên máy chủ")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.padding(.vertical, 4)
                                }
                            } else {
                                Text("Giọng ElevenLabs do admin cấp — bạn chỉ cần nhập Voice ID ở trên và chỉnh tốc độ. Không cần API key.")
                                    .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                            }
                        }
                    }

                    // ----- Chọn giọng (tách thành các view con để trình biên dịch không quá tải) -----
                    if tts.engineType == .system { systemVoiceSection }
                    if tts.engineType == .siri { siriVoiceSection }
                }
                .padding()
            }
            .navigationTitle(store.t("Đọc (TTS)", "Read (TTS)"))
            .onChange(of: readTypes) { v in
                UserDefaults.standard.set(v.sorted().joined(separator: ","), forKey: "tts_read_types")
            }
            // Tải lại kho âm DÙNG CHUNG mỗi khi mở màn (ai thêm thì mọi người đều thấy)
            .task { await store.loadNotifSounds(); tts.reloadNotif() }
            .task {
                // Bơm thông tin máy chủ để đọc ElevenLabs bằng KEY DÙNG CHUNG (admin đặt).
                tts.serverBase = store.baseURL
                tts.serverToken = store.token
                if let cfg = try? await store.api.storeConfig() {
                    tts.elevenServerKey = (cfg.elevenServerKey ?? false)
                }
            }
            // ĐỒNG BỘ THIẾT LẬP TTS TỪ MÁY CHỦ (theo tài khoản) — chỉ kéo 1 lần mỗi phiên.
            .task { await pullTTSSettings() }
            // Rời màn / đổi tab → đẩy thiết lập hiện tại lên máy chủ để lưu.
            .onDisappear { pushTTSSettings() }
            // App vào nền → cũng lưu (phòng khi bị tắt app mà chưa rời màn).
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                pushTTSSettings()
            }
        }
    }

    /// Kéo cấu hình TTS đã lưu trên máy chủ về & áp dụng (1 lần/phiên). Nếu máy chủ chưa có
    /// thì đẩy cấu hình hiện tại lên để lần sau có.
    private func pullTTSSettings() async {
        guard !ttsSyncedFromServer, store.token != nil else { return }
        ttsSyncedFromServer = true
        if let json = try? await store.api.getTTSSettings(), !json.isEmpty {
            if TTSSettingsSync.apply(json: json) {
                tts.reloadFromDefaults()
                readTypes = TTSView.loadReadTypes()   // @State cần nạp lại thủ công
            }
        } else {
            // Máy chủ chưa có → lưu cấu hình hiện tại lên để đồng bộ về sau.
            pushTTSSettings()
        }
    }

    /// Đẩy toàn bộ thiết lập TTS hiện tại lên máy chủ (theo tài khoản).
    private func pushTTSSettings() {
        guard store.token != nil else { return }
        let json = TTSSettingsSync.snapshotJSON()
        guard !json.isEmpty else { return }
        Task { try? await store.api.saveTTSSettings(json) }
    }

    // ----- Âm thanh thông báo cho 3 sự kiện: tặng quà · follow · chia sẻ -----
    private let notifEventLabels: [(id: String, label: String, icon: String)] = [
        ("gift",   "Tặng quà", "gift.fill"),
        ("follow", "Follow",   "heart.fill"),
        ("share",  "Chia sẻ",  "square.and.arrow.up.fill")
    ]

    // ----- Tự động đọc thông báo định kỳ: bật/tắt · sửa chữ · sửa phút · nghe thử -----
    @ViewBuilder private var autoAnnounceSection: some View {
        section("Tự động đọc thông báo (định kỳ)") {
            Text("Cứ sau N phút, app tự đọc câu thông báo bên dưới bằng ĐÚNG giọng đang chọn (ElevenLabs · Google · iOS · Siri). Ai cũng dùng được.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle(isOn: $tts.autoAnnounceOn) {
                Label("Bật tự động đọc thông báo", systemImage: "megaphone.fill").font(.subheadline)
            }.tint(Theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nội dung thông báo:").font(.caption).bold()
                TextEditor(text: $tts.autoAnnounceText)
                    .font(.body).frame(minHeight: 70)
                    .padding(6).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Đọc mỗi").font(.caption)
                    Spacer()
                    Text(String(format: "%.1f phút", tts.autoAnnounceMinutes))
                        .font(.caption2.bold()).foregroundStyle(Theme.accent)
                }
                Slider(value: $tts.autoAnnounceMinutes, in: 0.5...120, step: 0.5)
                Text("Từ 0,5 đến 120 phút. (Tối thiểu thực tế 30 giây để đọc kịp.)")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Button { tts.previewAutoAnnounce() } label: {
                    Label("Nghe thử", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                    .disabled(tts.autoAnnounceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button { tts.stop() } label: {
                    Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }

            if tts.autoAnnounceOn {
                Label("Đang bật · đọc mỗi \(String(format: "%.1f", tts.autoAnnounceMinutes)) phút bằng giọng \(tts.engineType.label).",
                      systemImage: "checkmark.circle.fill")
                    .font(.caption2).foregroundStyle(.green)
            }
        }
    }

    // ----- Tự động cà khịa lại bình luận khiêu khích (clap-back) -----
    @ViewBuilder private var autoRoastSection: some View {
        section("Tự động cà khịa lại (clap-back)") {
            Text("Khi có bình luận khiêu khích / anti (chứa từ như ngu, gà, kém, chửi thề…), bot tự đọc lại 1 câu cà khịa vui NGAY SAU bình luận đó — bằng giọng đang chọn.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle(isOn: $tts.autoRoastOn) {
                Label("Bật tự động cà khịa lại", systemImage: "flame.fill").font(.subheadline)
            }.tint(Theme.accent)
            Button { tts.speak(tts.randomRoast(name: "Minh")) } label: {
                Label("Nghe thử 1 câu cà khịa", systemImage: "play.circle.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            Text("Câu cà khịa vui, không chửi tục. Bot GỌI TÊN người bình luận rồi mới khịa. Chỉ kích hoạt với bình luận có ý khiêu khích.")
                .font(.caption2).foregroundStyle(.secondary)

            Divider().padding(.vertical, 2)

            // ---- Tự thêm câu cà khịa (lưu trên máy, không cần build lại) ----
            Text("Câu cà khịa của bạn — tự thêm ngay trong app:").font(.caption).bold()
            Text("Mẹo: gõ {name} vào chỗ muốn chèn tên người (vd: \"{name} ơi, khịa gì kỳ vậy\"). Không gõ {name} thì bot tự thêm \"tên ơi,\" phía trước.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                TextField("Nhập câu cà khịa rồi bấm +", text: $newRoast)
                    .autocorrectionDisabled()
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    tts.addCustomRoast(newRoast); newRoast = ""
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .disabled(newRoast.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if tts.customRoasts.isEmpty {
                Text("Chưa có câu nào của bạn. Bot sẽ dùng \(TTSEngine.roastComebacks.count) câu mặc định.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(tts.customRoasts, id: \.self) { line in
                        HStack(spacing: 8) {
                            Button { tts.speak(tts.renderRoast(line, name: "Minh")) } label: {
                                Image(systemName: "play.circle.fill")
                            }.buttonStyle(.plain).foregroundStyle(.green)
                            Text(line).font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button { tts.removeCustomRoast(line) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }.buttonStyle(.plain).foregroundStyle(.red)
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
                Text("Bot đọc ngẫu nhiên trong \(TTSEngine.roastComebacks.count + tts.customRoasts.count) câu (mặc định + của bạn).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var notifSoundSection: some View {
        section("Âm thanh thông báo (như TikFinity) · phát TRƯỚC khi đọc") {
            Text("Hơn 50 âm + KHO âm tùy chỉnh KHÔNG GIỚI HẠN: dán link .mp3 liên tiếp, tải nhiều file cùng lúc, hoặc trích âm thanh từ video. Mỗi âm dùng được cho cả Tặng quà/Follow/Chia sẻ.")
                .font(.caption2).foregroundStyle(.secondary)
            Text(store.isAdmin
                 ? "Bạn là ADMIN: chỉnh xong bấm “Đồng bộ lên server” ở cuối mục để MỌI khách dùng được (cài lại app vẫn còn)."
                 : "Âm bạn tự thêm lưu trên máy này. Bộ âm dùng chung do quản trị đồng bộ sẽ tự tải về khi mở app.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Nguồn âm meme miễn phí: myinstants.com · freesound.org · pixabay.com/sound-effects.")
                .font(.caption2).foregroundStyle(.secondary)
            customLibraryControls
            Divider()
            ForEach(notifEventLabels, id: \.id) { ev in
                soundChipRow(ev.id, label: ev.label, icon: ev.icon)
            }
            adminSyncControls
        }
        .sheet(isPresented: $showAudioImporter) {
            // Bộ chọn file có ô TÍCH (✓) + nút "Mở"; nhận mọi file âm thanh.
            DocumentPicker(contentTypes: [.audio, .mpeg4Audio, .mp3, .wav], allowsMultipleSelection: true, asCopy: true) { urls in
                let t = audioImportType
                Task { await uploadAudioBatch(urls, for: t) }
            }.ignoresSafeArea()
        }
    }

    // Khu vực thêm âm vào KHO tùy chỉnh (dán link / tải file / trích video) + danh sách kho.
    @ViewBuilder private var customLibraryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kho âm tùy chỉnh — dán link liên tiếp để thêm (không giới hạn):")
                .font(.caption).bold()
            HStack {
                TextField("Dán link .mp3 rồi bấm +", text: $newCustomLink)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.caption)
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    tts.addCustomSound(url: newCustomLink)
                    newCustomLink = ""
                    Task { await store.saveNotifSounds() }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                    .disabled(newCustomLink.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Button {
                    audioImportType = "__lib"; showAudioImporter = true
                } label: {
                    Label("Tải file âm thanh", systemImage: "square.and.arrow.up").font(.caption)
                }.buttonStyle(.bordered).disabled(audioUploading)
                if audioUploading {
                    ProgressView().scaleEffect(0.7)
                    Text(audioTotal > 1 ? "Đang tải \(audioDone)/\(audioTotal)…" : "Đang tải…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let audioError {
                Text("⚠️ " + audioError).font(.caption2).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Muốn trích âm thanh TỪ VIDEO → vào Khám phá › Chuyển đổi › tab \"Trích âm thanh → mp3\", lấy link rồi dán vào ô trên.")
                .font(.caption2).foregroundStyle(.secondary)
            let lib = tts.customSounds()
            if !lib.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lib.indices, id: \.self) { i in
                            let url = lib[i]["url"] ?? ""
                            HStack(spacing: 5) {
                                Button { tts.previewCustomUrl(url) } label: {
                                    Image(systemName: "play.circle.fill")
                                }.buttonStyle(.plain).foregroundStyle(.green)
                                Text(lib[i]["name"] ?? "Âm").font(.caption2).lineLimit(1)
                                Button { tts.removeCustomSound(url: url); Task { await store.saveNotifSounds() } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }.buttonStyle(.plain).foregroundStyle(.red)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground)).clipShape(Capsule())
                        }
                    }.padding(.vertical, 2)
                }
            }
        }
    }

    /// Nút ĐỒNG BỘ LÊN SERVER — CHỈ ADMIN thấy. Admin bấm → bộ âm (3 sự kiện + kho tùy chỉnh)
    /// được lưu dùng chung; MỌI khách mở app sẽ tải về và dùng được ngay.
    @ViewBuilder private var adminSyncControls: some View {
        if store.isAdmin {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Label("Quản trị: bộ âm dùng chung cho khách", systemImage: "person.badge.key.fill")
                    .font(.caption.bold()).foregroundStyle(Theme.accent)
                Text("Chỉnh xong bộ âm ở trên rồi bấm ĐỒNG BỘ. Khách KHÔNG thấy nút này — họ chỉ nhận & dùng bộ âm bạn đã đồng bộ (khách vẫn tự thêm âm riêng, lưu trên máy họ).")
                    .font(.caption2).foregroundStyle(.secondary)
                Button {
                    Task {
                        syncing = true; syncMsg = nil
                        let ok = await store.saveNotifSounds()
                        syncing = false
                        syncMsg = ok ? "Đã đồng bộ lên server — khách dùng được ngay."
                                     : "Đồng bộ thất bại. Kiểm tra mạng rồi thử lại."
                    }
                } label: {
                    HStack {
                        if syncing { ProgressView().scaleEffect(0.8).padding(.trailing, 2) }
                        Label(syncing ? "Đang đồng bộ…" : "Đồng bộ lên server (cho khách dùng)",
                              systemImage: "icloud.and.arrow.up.fill")
                            .frame(maxWidth: .infinity)
                    }
                }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(syncing)
                if let syncMsg {
                    Text(syncMsg).font(.caption2)
                        .foregroundStyle(syncMsg.hasPrefix("Đã đồng bộ") ? .green : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Tải NHIỀU file âm thanh cùng lúc — SONG SONG (3 file/lượt), stream thẳng (nhanh, ít RAM),
    /// CÓ THỬ LẠI khi lỗi mạng; đếm tiến độ. type=="__lib" thêm vào kho; còn lại gán cho sự kiện.
    private func uploadAudioBatch(_ urls: [URL], for type: String) async {
        let items = urls
        guard !items.isEmpty else { return }
        audioUploading = true; audioError = nil
        audioTotal = items.count; audioDone = 0

        struct Uploaded { let name: String; let url: String?; let server: Bool }
        let api = store.api

        // Mỗi file: thử stream lên server (THỬ LẠI tối đa 3 lần khi lỗi mạng/máy chủ bận);
        // vẫn lỗi thì lưu vào máy (dùng được ngay, không mất file).
        func upload(_ url: URL) async -> Uploaded {
            let name = url.lastPathComponent
            let mime = name.lowercased().hasSuffix(".wav") ? "audio/wav"
                     : name.lowercased().hasSuffix(".m4a") ? "audio/mp4" : "audio/mpeg"
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let attempts = 3
            for attempt in 1...attempts {
                do {
                    let link = try await api.mediaUploadRaw(name: name, mime: mime, fileURL: url)
                    return Uploaded(name: name, url: link, server: true)
                } catch {
                    // Còn lượt → chờ tăng dần (0.6s, 1.4s) rồi thử lại.
                    if attempt < attempts {
                        let ns = UInt64(0.6 * Double(attempt) * 1_000_000_000) + 800_000_000
                        try? await Task.sleep(nanoseconds: ns)
                    }
                }
            }
            // Hết lượt lên server → lưu vào máy để KHÔNG mất file, vẫn phát được.
            if let data = try? Data(contentsOf: url), !data.isEmpty,
               let localURL = saveAudioLocally(data, name: name) {
                return Uploaded(name: name, url: localURL, server: false)
            }
            return Uploaded(name: name, url: nil, server: false)
        }

        var results: [Uploaded] = []
        await withTaskGroup(of: Uploaded.self) { group in
            // 3 file/lượt: cân bằng nhanh & ổn định (nhiều quá dễ nghẽn mạng/máy chủ → lỗi).
            let maxConc = 3
            var idx = 0
            while idx < items.count && idx < maxConc { let u = items[idx]; group.addTask { await upload(u) }; idx += 1 }
            while let r = await group.next() {
                results.append(r)
                audioDone += 1
                if idx < items.count { let u = items[idx]; group.addTask { await upload(u) }; idx += 1 }
            }
        }

        // Áp kết quả vào kho / sự kiện (trên main — đang ở MainActor).
        for r in results where r.url != nil {
            if type == "__lib" {
                tts.addCustomSound(url: r.url!, name: r.name)
            } else {
                tts.setNotifSound("custom", for: type)
                tts.setNotifSoundUrl(r.url!, for: type)
            }
        }
        await store.saveNotifSounds()

        let okServer = results.filter { $0.server }.count
        let localOnly = results.filter { $0.url != nil && !$0.server }.count
        let failed = results.filter { $0.url == nil }.count
        if failed == 0 && localOnly == 0 {
            audioError = nil
        } else {
            var parts: [String] = ["Đã tải \(okServer)/\(items.count) file lên máy chủ"]
            if localOnly > 0 { parts.append("\(localOnly) lưu tạm trên máy (máy chủ bận)") }
            if failed > 0 { parts.append("\(failed) file lỗi") }
            audioError = parts.joined(separator: " · ") + "."
        }
        audioUploading = false; audioTotal = 0; audioDone = 0
    }

    /// Lưu dữ liệu âm thanh vào thư mục app (dùng được offline, còn sau khi tắt app).
    private func saveAudioLocally(_ data: Data, name: String) -> String? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("notif_sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.isEmpty ? "audio.mp3" : name
        let dest = dir.appendingPathComponent("\(Int(Date().timeIntervalSince1970))_\(safe)")
        do { try data.write(to: dest); return dest.absoluteString }
        catch { return nil }
    }

    // Binding 2 chiều cho link âm thanh tùy chỉnh của 1 sự kiện.
    private func notifUrlBinding(_ type: String) -> Binding<String> {
        Binding(get: { tts.notifSoundUrl(for: type) },
                set: { tts.setNotifSoundUrl($0, for: type) })
    }

    @ViewBuilder private func soundChipRow(_ type: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: icon).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                Spacer()
                // Nghe thử đúng âm đang chọn cho sự kiện này (kể cả link tùy chỉnh)
                Button { tts.previewNotif(for: type) } label: {
                    Label("Nghe thử", systemImage: "play.circle.fill").font(.caption)
                }.buttonStyle(.plain).foregroundStyle(.green)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kNotifSounds) { s in
                        let on = tts.notifSoundId(for: type) == s.id
                        Button {
                            // Chạm = chọn âm; âm tổng hợp thì nghe thử luôn (custom đợi dán link).
                            if s.id != "none" && s.id != "custom" { tts.previewNotifSound(s.id) }
                            tts.setNotifSound(s.id, for: type)
                            Task { await store.saveNotifSounds() }   // lưu lên máy chủ
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: s.icon).font(.body)
                                Text(s.label).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72, height: 56)
                            .background(on ? Theme.accent.opacity(0.28) : Color(.secondarySystemBackground))
                            .foregroundStyle(on ? Theme.accent : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2).foregroundStyle(.green)
                                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                                        .offset(x: -3, y: 3)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                    // Âm từ KHO tùy chỉnh — gán nhanh cho sự kiện này
                    ForEach(tts.customSounds().indices, id: \.self) { i in
                        let url = tts.customSounds()[i]["url"] ?? ""
                        let nm = tts.customSounds()[i]["name"] ?? "Âm"
                        let on = tts.notifSoundId(for: type) == "custom" && tts.notifSoundUrl(for: type) == url
                        Button {
                            tts.setNotifSound("custom", for: type)
                            tts.setNotifSoundUrl(url, for: type)
                            tts.previewCustomUrl(url)
                            Task { await store.saveNotifSounds() }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: "music.note").font(.body)
                                Text(nm).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72, height: 56)
                            .background(on ? Theme.accent.opacity(0.28) : Color(.secondarySystemBackground))
                            .foregroundStyle(on ? Theme.accent : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : .clear, lineWidth: 1.5))
                            .overlay(alignment: .topTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption2).foregroundStyle(.green)
                                        .background(Circle().fill(.white).frame(width: 12, height: 12))
                                        .offset(x: -3, y: 3)
                                }
                            }
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            // Ô dán link / tải file khi chọn "Tùy chỉnh" — dùng âm meme tùy ý (mp3).
            if tts.notifSoundId(for: type) == "custom" {
                TextField("Dán link .mp3 (vd meme cười, la hét, airhorn…)", text: notifUrlBinding(type))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL).font(.caption)
                    .submitLabel(.done)
                    .onSubmit { Task { await store.saveNotifSounds() } }   // lưu link lên máy chủ
                    .padding(8).background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button {
                        audioImportType = type; showAudioImporter = true
                    } label: {
                        Label(audioUploading
                                ? (audioTotal > 1 ? "Đang tải \(audioDone)/\(audioTotal)…" : "Đang tải lên…")
                                : "Tải file âm thanh từ máy",
                              systemImage: "square.and.arrow.up").font(.caption)
                    }.buttonStyle(.bordered).disabled(audioUploading)
                    Spacer()
                    Button { Task { await store.saveNotifSounds() } } label: {
                        Label("Lưu", systemImage: "checkmark.circle.fill").font(.caption)
                    }.buttonStyle(.bordered).tint(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // ----- Chọn giọng hệ thống (iOS mặc định) — layout đồng bộ ElevenLabs -----
    @ViewBuilder private var systemVoiceSection: some View {
        section("Giọng đọc hệ thống (\(Self.cachedVoices.count) giọng · \(vietnameseVoiceCount) tiếng Việt)") {
            Text("Chọn 1 giọng có sẵn trên máy để đọc tiếng Việt. Bấm loa để nghe thử.")
                .font(.caption2).foregroundStyle(.secondary)

            selectedVoiceBadge(voiceName(for: tts.voiceId))

            Divider().padding(.vertical, 4)

            Toggle(isOn: $onlyVietnameseVoices) {
                Label("Chỉ hiện giọng tiếng Việt", systemImage: "flag.fill").font(.subheadline)
            }.tint(Theme.accent)
            textField("Tìm theo tên / ngôn ngữ (vd: vi, English)", $search)

            VStack(spacing: 0) {
                ForEach(voices, id: \.identifier) { v in
                    voiceRow(v, selected: tts.voiceId == v.identifier) { tts.voiceId = v.identifier }
                }
            }
            Text("Muốn thêm giọng tự nhiên hơn: iOS → Cài đặt → Trợ năng → Nội dung nói → Giọng nói → tải thêm.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // ----- Chọn giọng cho chế độ "Giọng Siri (iOS)" — layout đồng bộ ElevenLabs -----
    @ViewBuilder private var siriVoiceSection: some View {
        section("Giọng Siri / iOS — chọn giọng có sẵn trên máy bạn") {
            Text("App đã tìm các giọng máy bạn đang có. Chọn 1 giọng (ưu tiên Cao cấp/Nâng cao nghe gần Siri nhất), bấm loa để nghe thử.")
                .font(.caption2).foregroundStyle(.secondary)

            selectedVoiceBadge(tts.siriVoiceId.isEmpty ? nil : voiceName(for: tts.siriVoiceId))

            Divider().padding(.vertical, 4)

            Button { tts.siriVoiceId = "" } label: {
                let auto = tts.siriVoiceId.isEmpty
                HStack {
                    Image(systemName: auto ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(auto ? Color.green : Theme.accent)
                    VStack(alignment: .leading) {
                        Text("Tự động (giọng tốt nhất)").font(.subheadline)
                            .foregroundStyle(auto ? Color.green : .primary)
                        Text("App tự chọn giọng chất lượng cao nhất").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if auto {
                        Text("Đang dùng").font(.caption2.bold()).foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.15)).clipShape(Capsule())
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, auto ? 8 : 0)
                .background(auto ? Color.green.opacity(0.10) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
            Divider()
            VStack(spacing: 0) {
                ForEach(siriCandidateVoices, id: \.identifier) { v in
                    voiceRow(v, selected: tts.siriVoiceId == v.identifier, highlightQuality: true) {
                        tts.siriVoiceId = v.identifier
                    }
                }
            }
            Text("Lưu ý: iOS chưa có giọng \"Siri\" riêng cho tiếng Việt — giọng Cao cấp (Linh) là gần Siri nhất. Muốn hay & tự nhiên hơn nữa, hãy dùng \"Chị Google (Online)\".")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // (Đã xoá chế độ "Siri Anh·Việt phiên âm" theo yêu cầu.)

    // Badge hiển thị giọng đang dùng — đồng bộ chỉ báo "Giọng: X" của ElevenLabs.
    @ViewBuilder private func selectedVoiceBadge(_ name: String?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "person.wave.2.fill").foregroundStyle(.green).font(.caption)
            Text(name != nil ? "Đang dùng: \(name!)" : "Tự động (giọng tốt nhất)")
                .font(.caption.bold()).foregroundStyle(.green)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Tên giọng theo identifier (để hiện badge "Đang dùng").
    private func voiceName(for id: String) -> String? {
        guard !id.isEmpty else { return nil }
        return Self.cachedVoices.first { $0.identifier == id }?.name
    }

    // Một hàng giọng: chọn + nghe thử. Tách ra để body nhẹ, biên dịch nhanh.
    @ViewBuilder private func voiceRow(_ v: AVSpeechSynthesisVoice, selected: Bool,
                                       highlightQuality: Bool = false,
                                       onSelect: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.green : Theme.accent)
                    VStack(alignment: .leading) {
                        Text(v.name).font(.subheadline)
                            .foregroundStyle(selected ? Color.green : .primary)
                        Text("\(v.language) · \(qualityText(v.quality))")
                            .font(.caption2)
                            .foregroundStyle(highlightQuality && v.quality != .default ? Color.green : Color.secondary)
                    }
                    Spacer()
                    if selected {
                        Text("Đang dùng").font(.caption2.bold()).foregroundStyle(.green)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.15)).clipShape(Capsule())
                    }
                }
            }.buttonStyle(.plain)
            Button {
                let u = AVSpeechUtterance(string: "Xin chào, đây là giọng đọc thử nghiệm.")
                u.voice = v
                u.rate = tts.rate
                u.pitchMultiplier = tts.pitch
                previewSynth.speak(u)
            } label: {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, selected ? 8 : 0)
        .background(selected ? Color.green.opacity(0.10) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        Divider()
    }

    // Tạo & đồng bộ đường dẫn trình đọc trên trình duyệt (TikTok Studio / OBS).
    private func makeReaderLink() async {
        let id = tiktokId.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return }
        readerBusy = true; readerMsg = nil
        let hasEleven = !tts.elevenVoiceId.trimmingCharacters(in: .whitespaces).isEmpty
        let engine = (tts.engineType == .elevenlabs && hasEleven) ? "eleven" : "browser"
        let model = UserDefaults.standard.string(forKey: "eleven_model") ?? "eleven_multilingual_v2"
        let tpl: [String: String] = [
            "comment": templateComment, "gift": templateGift, "follow": templateFollow,
            "share": templateShare, "join": templateJoin,
        ]
        do {
            let url = try await store.api.saveReaderConfig(
                username: id, engine: engine,
                voiceId: tts.elevenVoiceId.trimmingCharacters(in: .whitespaces),
                model: model, speed: tts.elevenSpeed, readTypes: Array(readTypes),
                translate: translateToVi, tpl: tpl)
            readerURL = url
            readerMsg = "Đã đồng bộ giọng. Mở đường dẫn trên máy phát live."
        } catch {
            readerMsg = "Lỗi tạo đường dẫn: \(error.localizedDescription)"
        }
        readerBusy = false
    }

    // Một dòng hướng dẫn: số thứ tự tròn + tiêu đề + mô tả.
    @ViewBuilder private func guideRow(_ n: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.caption2.bold()).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.bold())
                Text(desc).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // ----- TikTok Live helpers -----
    private var liveStatusText: String {
        if !liveConnected && liveStatus.isEmpty { return "Chưa kết nối" }
        switch liveStatus {
        case "connecting": return "Đang kết nối tới phòng LIVE..."
        case "connected":  return "Đã kết nối · đang đọc bình luận"
        case "ended":      return "Phiên LIVE đã kết thúc"
        case "error":      return "Lỗi kết nối"
        default:           return liveConnected ? "Đang đọc" : "Chưa kết nối"
        }
    }
    private var liveStatusColor: Color {
        switch liveStatus {
        case "connected": return .green
        case "connecting": return .orange
        case "error", "ended": return .red
        default: return .gray
        }
    }

    /// Dòng CHẨN ĐOÁN: máy chủ THỰC SỰ nhận được loại sự kiện nào (theo tên lớp TikTokLive).
    /// Giúp biết ngay lỗi nằm ở "không bắt được bình luận" hay ở "đọc".
    @ViewBuilder private var liveDiagnosticLine: some View {
        if !liveCounts.isEmpty {
            let cmt = liveCounts["CommentEvent"] ?? 0
            let join = liveCounts["JoinEvent"] ?? 0
            let gift = liveCounts["GiftEvent"] ?? 0
            let follow = liveCounts["FollowEvent"] ?? 0
            let like = liveCounts["LikeEvent"] ?? 0
            VStack(alignment: .leading, spacing: 2) {
                Text("Máy chủ nhận: 💬 \(cmt) · 👤 \(join) · 🎁 \(gift) · ❤️ \(follow)"
                     + (like > 0 ? " · 👍 \(like)" : ""))
                    .font(.caption2).foregroundStyle(.secondary)
                if cmt == 0 && (join + gift + follow + like) > 0 {
                    Text("⚠️ Kết nối OK nhưng CHƯA nhận được bình luận nào từ TikTok — thường cần khoá ký (sign key). Báo người quản trị đặt TIKTOK_SIGN_KEY.")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func renderLive(_ ev: TikTokLiveEvent) -> String {
        let template: String
        switch ev.type {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = ev.name.isEmpty ? "bạn" : ev.name
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: ev.content)
            .trimmingCharacters(in: .whitespaces)
    }

    private func connectLive() {
        let id = tiktokId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        liveError = nil; liveFeed = []; lastEventId = 0; liveCounts = [:]
        liveStatus = "connecting"; liveConnected = true
        
        tts.startBackgroundMode() // Giữ app chạy ngầm bằng silent audio loop
        
        Task {
            do {
                let s = try await store.api.tiktokLiveConnect(username: id)
                liveStatus = s.status
                // BỎ QUA bình luận CŨ: lúc vừa kết nối, TikTok dồn về 1 loạt bình luận
                // trước đó. Chờ ~2.5s cho loạt cũ dồn hết rồi NHẢY QUA toàn bộ (không đọc),
                // chỉ đọc bình luận MỚI phát sinh SAU khi kết nối → không đọc lại cả live.
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if !Task.isCancelled,
                   let drain = try? await store.api.tiktokLiveEvents(username: id, after: lastEventId) {
                    lastEventId = drain.last
                    liveStatus = drain.status
                }
                startPolling(id)
            } catch {
                liveError = error.localizedDescription
                liveStatus = "error"; liveConnected = false
                tts.stopBackgroundMode()
            }
        }
    }

    private func startPolling(_ id: String) {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let r = try await store.api.tiktokLiveEvents(username: id, after: lastEventId)
                    liveStatus = r.status
                    if let c = r.counts { liveCounts = c }
                    if let e = r.error { liveError = e }
                    for ev in r.events {
                        // CHỈ hiện các loại sự kiện ĐANG BẬT lên bảng tin → khi tắt "Người vào",
                        // lời chào người vào KHÔNG tràn bảng tin nữa, BÌNH LUẬN mới hiện rõ.
                        guard readTypes.contains(ev.type) else { continue }
                        // Bình luận lên ĐẦU danh sách chờ đọc (announce ưu tiên comment > join).
                        liveFeed.append(ev)
                        let text = await liveSpeechText(ev)
                        // Phát âm thanh thông báo (quà/follow/share) TRƯỚC rồi mới đọc.
                        tts.announce(text, eventType: ev.type)
                        // Tự động CÀ KHỊA lại bình luận khiêu khích: GỌI TÊN người rồi khịa,
                        // đọc NGAY SAU bình luận đó.
                        if ev.type == "comment", tts.autoRoastOn, tts.shouldRoast(ev.content) {
                            tts.announce(tts.randomRoast(name: cleanLiveName(ev.name)), eventType: "comment")
                        }
                    }
                    if liveFeed.count > 120 { liveFeed.removeFirst(liveFeed.count - 120) }
                    lastEventId = r.last
                    if r.status == "ended" || r.status == "error" { break }
                } catch {
                    // bỏ qua lỗi mạng tạm thời, thử lại ở vòng sau
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func disconnectLive() {
        pollTask?.cancel(); pollTask = nil
        liveConnected = false
        liveStatus = ""
        tts.stopBackgroundMode() // Tắt chạy ngầm
        let id = tiktokId.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { try? await store.api.tiktokLiveDisconnect(username: id) }
    }

    /// Dịch nội dung 1 sự kiện live sang tiếng Việt (giữ tên người + mẫu câu Việt), rồi trả về câu để đọc.
    private func liveSpeechText(_ ev: TikTokLiveEvent) async -> String {
        var content = ev.content
        if translateToVi, !content.isEmpty {
            if let tr = try? await store.api.translate(text: content), !tr.text.isEmpty {
                content = tr.text
            }
        }
        // KIỂM SOÁT CHÍNH TẢ TRỰC TIẾP TRÊN BÌNH LUẬN — áp cho MỌI giọng (kể cả iOS/Siri):
        // mở rộng tiếng lóng/viết tắt, phục hồi dấu chữ không dấu, đọc rõ chữ cái.
        if !content.isEmpty {
            content = VietnameseTextNormalizer.normalize(content)
        }
        let template: String
        switch ev.type {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = cleanLiveName(ev.name)
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: content)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Làm SẠCH tên người xem để ĐỌC RÕ & ĐÚNG:
    /// 1) Chuẩn hoá FONT LẠ về chữ thường (NFKC): 𝓜𝓲𝓷𝓱→Minh · Ⓜⓘⓝⓗ→Minh · ｆｕｌｌ→full …
    /// 2) Bỏ emoji/ký hiệu; đổi _ - . thành khoảng trắng; giữ chữ-số (kể cả tiếng Việt có dấu).
    /// Tên rỗng/không đọc được → "bạn".
    private func cleanLiveName(_ raw: String) -> String {
        let normalized = raw.precomposedStringWithCompatibilityMapping   // NFKC — quy font lạ về chữ chuẩn
        var out = ""
        for ch in normalized {
            if ch.isLetter || ch.isNumber || ch == " " {
                out.append(ch)
            } else if ch == "_" || ch == "-" || ch == "." {
                out.append(" ")            // tách token dính nhau → đọc rõ hơn
            }
            // emoji/ký hiệu khác → bỏ
        }
        out = out.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? "bạn" : out
    }

    /// Đọc 1 đoạn text: nếu bật dịch thì dịch sang tiếng Việt trước rồi mới đọc.
    /// Có eventType (gift/follow/share) → phát âm thanh thông báo TRƯỚC khi đọc.
    private func speakTranslated(_ text: String, eventType: String? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        func read(_ s: String) {
            if let ev = eventType { tts.announce(s, eventType: ev) } else { tts.speak(s) }
        }
        if translateToVi {
            Task {
                if let tr = try? await store.api.translate(text: t), !tr.text.isEmpty {
                    read(tr.text)
                } else {
                    read(t)
                }
            }
        } else {
            read(t)
        }
    }

    // ----- helpers -----
    private func renderEvent() -> String {
        let template: String
        switch selectedEvent {
        case "join": template = templateJoin
        case "gift": template = templateGift
        case "comment": template = templateComment
        case "follow": template = templateFollow
        case "share": template = templateShare
        default: template = "{name} bình luận: {content}"
        }
        let name = personName.isEmpty ? "bạn" : personName
        return template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{content}", with: content.isEmpty ? "" : content)
            .trimmingCharacters(in: .whitespaces)
    }
    private func qualityText(_ q: AVSpeechSynthesisVoiceQuality) -> String {
        switch q {
        case .enhanced: return "nâng cao"
        case .premium:  return "cao cấp"
        default:        return "thường"
        }
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
        }
        .padding(12)
        .kCard(12)
    }
    private func textField(_ ph: String, _ text: Binding<String>) -> some View {
        TextField(ph, text: text)
            .padding(8).background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private func slider(_ label: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue)).font(.caption2).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
    // Bản Double (dùng cho tốc độ ElevenLabs 0.5–2.0)
    private func sliderD(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text(String(format: "%.2f×", value.wrappedValue)).font(.caption2.bold()).foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: range)
        }
    }
}

